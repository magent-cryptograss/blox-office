// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Chartifacts.sol";

// A picker "wallet" that tries to collect twice in one go.
contract GreedyWallet {
    Chartifacts chartifacts;
    uint256 public timesPaid;

    constructor(Chartifacts _chartifacts) {
        chartifacts = _chartifacts;
    }

    function collect() external {
        chartifacts.collect();
    }

    receive() external payable {
        timesPaid++;
        if (timesPaid < 3) {
            try chartifacts.collect() {} catch {}
        }
    }
}

contract ChartifactsTests is Test {
    Chartifacts chartifacts;

    address band = makeAddr("band");
    address harry = makeAddr("harry");
    address kyle = makeAddr("kyle");
    address fan = makeAddr("fan");
    address otherFan = makeAddr("otherFan");
    address stranger = makeAddr("stranger");

    string constant CUT = "QmS3QEZFa1c75BBa9vwNEsXkS6GBmS75Cs6RyDJBXqRx8a";
    uint256 constant PRICE = 0.01 ether;

    uint256 harrys; // Harry Clark's chart for August: 100 shares, 40% to Harry
    uint256 kyles;  // Kyle Tuttle's: 100 shares, no wallet yet

    function setUp() public {
        vm.prank(band);
        chartifacts = new Chartifacts("https://example.invalid/{id}.json");

        vm.startPrank(band);
        harrys = chartifacts.list("August", "Harry Clark", CUT, "", 100, PRICE, 40, bytes32(0));
        chartifacts.setPickerWallet(harrys, harry);
        kyles = chartifacts.list("August", "Kyle Tuttle", CUT, "", 100, PRICE, 40, bytes32(0));
        vm.stopPrank();

        vm.deal(fan, 100 ether);
        vm.deal(otherFan, 100 ether);
        vm.deal(stranger, 100 ether);
    }

    // ---- listing ----

    function testListingRecordsWhatItIs() public view {
        (string memory song, string memory picker, string memory cut, string memory part, uint256 shares,
            uint256 spokenFor, uint256 price, address pickerWallet, uint256 pickerPercent, bytes32 paperSeal) =
            chartifacts.chartifacts(harrys);
        assertEq(song, "August");
        assertEq(picker, "Harry Clark");
        assertEq(cut, CUT);
        assertEq(part, "");
        assertEq(shares, 100);
        assertEq(spokenFor, 0);
        assertEq(price, PRICE);
        assertEq(pickerWallet, harry);
        assertEq(pickerPercent, 40);
        assertEq(paperSeal, bytes32(0));
        assertEq(chartifacts.count(), 2);
        assertEq(chartifacts.sharesLeft(harrys), 100);
    }

    function testOnlyTheBandLists() public {
        vm.prank(stranger);
        vm.expectRevert("only the band can do this");
        chartifacts.list("August", "Maddie Denton", CUT, "", 100, PRICE, 0, bytes32(0));
    }

    function testSameChartCannotBeListedTwice() public {
        vm.prank(band);
        vm.expectRevert("this chart is already listed");
        chartifacts.list("August (again)", "Harry Clark", CUT, "", 5, 1, 0, bytes32(0));
    }

    function testSamePickerMayHaveSeparateParts() public {
        vm.prank(band);
        uint256 id = chartifacts.list("August", "Harry Clark", CUT, "third A part", 10, PRICE, 40, bytes32(0));
        assertEq(id, 2);
    }

    function testFieldsCannotBeShuffledIntoADuplicate() public {
        // "ab" + "c" and "a" + "bc" must not count as the same chart.
        vm.startPrank(band);
        chartifacts.list("x", "c", "ab", "", 1, 1, 0, bytes32(0));
        chartifacts.list("x", "bc", "a", "", 1, 1, 0, bytes32(0));
        vm.stopPrank();
    }

    function testListingRefusesNoSharesAndBadPercent() public {
        vm.startPrank(band);
        vm.expectRevert("a chartifact needs at least one share");
        chartifacts.list("August", "Maddie Denton", CUT, "", 0, PRICE, 0, bytes32(0));
        vm.expectRevert("a percent is 0 to 100");
        chartifacts.list("August", "Maddie Denton", CUT, "", 100, PRICE, 101, bytes32(0));
        vm.stopPrank();
    }

    // ---- buying ----

    function testBuyingGivesSharesAndSplitsTheMoney() public {
        vm.prank(fan);
        chartifacts.buy{value: 3 * PRICE}(harrys, 3);

        assertEq(chartifacts.balanceOf(fan, harrys), 3);
        assertEq(chartifacts.sharesLeft(harrys), 97);
        assertEq(chartifacts.owed(harry), (3 * PRICE * 40) / 100);
        assertEq(chartifacts.owed(band), 3 * PRICE - (3 * PRICE * 40) / 100);
        assertEq(address(chartifacts).balance, 3 * PRICE);
    }

    function testWithNoPickerWalletItAllWaitsForTheBand() public {
        vm.prank(fan);
        chartifacts.buy{value: 2 * PRICE}(kyles, 2);
        assertEq(chartifacts.owed(band), 2 * PRICE);
        assertEq(chartifacts.owed(address(0)), 0);
    }

    function testAPickerWalletRecordedLaterGetsLaterSales() public {
        vm.prank(fan);
        chartifacts.buy{value: PRICE}(kyles, 1);

        vm.prank(band);
        chartifacts.setPickerWallet(kyles, kyle);

        vm.prank(fan);
        chartifacts.buy{value: PRICE}(kyles, 1);

        assertEq(chartifacts.owed(kyle), (PRICE * 40) / 100);
        assertEq(chartifacts.owed(band), PRICE + PRICE - (PRICE * 40) / 100);
    }

    function testOnlyTheBandRecordsAPickerWallet() public {
        vm.prank(stranger);
        vm.expectRevert("only the band can do this");
        chartifacts.setPickerWallet(kyles, stranger);
    }

    function testWrongMoneyIsRefused() public {
        vm.startPrank(fan);
        vm.expectRevert("send exactly the price");
        chartifacts.buy{value: PRICE - 1}(harrys, 1);
        vm.expectRevert("send exactly the price");
        chartifacts.buy{value: PRICE + 1}(harrys, 1);
        vm.expectRevert("send exactly the price");
        chartifacts.buy{value: 0}(harrys, 1);
        vm.stopPrank();
    }

    function testCannotBuyMoreThanThereIs() public {
        vm.prank(fan);
        chartifacts.buy{value: 99 * PRICE}(harrys, 99);

        vm.prank(otherFan);
        vm.expectRevert("not that many shares left");
        chartifacts.buy{value: 2 * PRICE}(harrys, 2);

        vm.prank(otherFan);
        chartifacts.buy{value: PRICE}(harrys, 1);
        assertEq(chartifacts.sharesLeft(harrys), 0);

        vm.prank(stranger);
        vm.expectRevert("not that many shares left");
        chartifacts.buy{value: PRICE}(harrys, 1);
    }

    function testBuyingAChartifactThatIsNotThereFails() public {
        vm.prank(fan);
        vm.expectRevert();
        chartifacts.buy{value: PRICE}(99, 1);
    }

    function testHoldingAll() public {
        vm.prank(fan);
        chartifacts.buy{value: 99 * PRICE}(harrys, 99);
        assertFalse(chartifacts.holdsAll(fan, harrys));

        vm.prank(fan);
        chartifacts.buy{value: PRICE}(harrys, 1);
        assertTrue(chartifacts.holdsAll(fan, harrys));
        assertFalse(chartifacts.holdsAll(otherFan, harrys));
    }

    function testAPriceChangeTouchesOnlyLaterSales() public {
        vm.prank(fan);
        chartifacts.buy{value: PRICE}(harrys, 1);

        vm.prank(band);
        chartifacts.setPrice(harrys, 2 * PRICE);

        vm.prank(fan);
        vm.expectRevert("send exactly the price");
        chartifacts.buy{value: PRICE}(harrys, 1);

        vm.prank(fan);
        chartifacts.buy{value: 2 * PRICE}(harrys, 1);
        assertEq(chartifacts.balanceOf(fan, harrys), 2);
    }

    function testOnlyTheBandSetsThePrice() public {
        vm.prank(stranger);
        vm.expectRevert("only the band can do this");
        chartifacts.setPrice(harrys, 0);
    }

    // ---- shares are the holder's own ----

    function testAHolderMovesSharesWithoutTheBand() public {
        vm.prank(fan);
        chartifacts.buy{value: 5 * PRICE}(harrys, 5);

        vm.prank(fan);
        chartifacts.safeTransferFrom(fan, otherFan, harrys, 2, "");
        assertEq(chartifacts.balanceOf(fan, harrys), 3);
        assertEq(chartifacts.balanceOf(otherFan, harrys), 2);
    }

    function testNobodyElseMovesAHoldersShares() public {
        vm.prank(fan);
        chartifacts.buy{value: 5 * PRICE}(harrys, 5);

        vm.prank(band);
        vm.expectRevert();
        chartifacts.safeTransferFrom(fan, band, harrys, 5, "");

        vm.prank(stranger);
        vm.expectRevert();
        chartifacts.safeTransferFrom(fan, stranger, harrys, 1, "");
    }

    // ---- giving ----

    function testTheBandGivesShares() public {
        vm.prank(band);
        chartifacts.give(harrys, harry, 10);
        assertEq(chartifacts.balanceOf(harry, harrys), 10);
        assertEq(chartifacts.sharesLeft(harrys), 90);
        assertEq(chartifacts.owed(band), 0);
    }

    function testGivingCountsAgainstTheShares() public {
        vm.prank(band);
        chartifacts.give(harrys, harry, 100);
        vm.prank(band);
        vm.expectRevert("not that many shares left");
        chartifacts.give(harrys, harry, 1);
    }

    function testOnlyTheBandGives() public {
        vm.prank(stranger);
        vm.expectRevert("only the band can do this");
        chartifacts.give(harrys, stranger, 1);
    }

    // ---- set aside, and claim ----

    function testSetAsideThenClaim() public {
        bytes32 codeHash = keccak256(bytes("goys-teeth-4417"));
        vm.prank(band);
        chartifacts.setAside(harrys, 2, codeHash);

        assertEq(chartifacts.sharesLeft(harrys), 98);
        assertEq(chartifacts.balanceOf(fan, harrys), 0);

        // Anyone holding the code can send the shares anywhere: here a
        // stranger (think: a relayer paying the gas) sends them to the fan.
        vm.prank(stranger);
        chartifacts.claim("goys-teeth-4417", fan);
        assertEq(chartifacts.balanceOf(fan, harrys), 2);
        assertEq(chartifacts.sharesLeft(harrys), 98);
    }

    function testACodeWorksOnce() public {
        vm.prank(band);
        chartifacts.setAside(harrys, 2, keccak256(bytes("once")));
        chartifacts.claim("once", fan);
        vm.expectRevert("no shares are waiting under that code");
        chartifacts.claim("once", fan);
    }

    function testAWrongCodeGetsNothing() public {
        vm.prank(band);
        chartifacts.setAside(harrys, 2, keccak256(bytes("right")));
        vm.expectRevert("no shares are waiting under that code");
        chartifacts.claim("wrong", stranger);
        vm.expectRevert("no shares are waiting under that code");
        chartifacts.claim("", stranger);
    }

    function testSharesSetAsideCannotBeBought() public {
        vm.prank(band);
        chartifacts.setAside(harrys, 100, keccak256(bytes("all of it")));
        vm.prank(fan);
        vm.expectRevert("not that many shares left");
        chartifacts.buy{value: PRICE}(harrys, 1);
    }

    function testACodeCannotBeUsedForTwoSetAsides() public {
        bytes32 codeHash = keccak256(bytes("same"));
        vm.startPrank(band);
        chartifacts.setAside(harrys, 1, codeHash);
        vm.expectRevert("that code is already in use");
        chartifacts.setAside(kyles, 1, codeHash);
        vm.expectRevert("set aside at least one share");
        chartifacts.setAside(kyles, 0, keccak256(bytes("empty")));
        vm.stopPrank();
    }

    function testOnlyTheBandSetsAside() public {
        vm.prank(stranger);
        vm.expectRevert("only the band can do this");
        chartifacts.setAside(harrys, 1, keccak256(bytes("mine")));
    }

    // ---- collecting ----

    function testPickerAndBandCollect() public {
        vm.prank(fan);
        chartifacts.buy{value: 10 * PRICE}(harrys, 10);

        vm.prank(harry);
        chartifacts.collect();
        assertEq(harry.balance, 4 * PRICE);
        assertEq(chartifacts.owed(harry), 0);

        vm.prank(band);
        chartifacts.collect();
        assertEq(band.balance, 6 * PRICE);
        assertEq(address(chartifacts).balance, 0);
    }

    function testNothingOwedNothingCollected() public {
        vm.prank(stranger);
        vm.expectRevert("nothing is owed to you");
        chartifacts.collect();

        vm.prank(fan);
        chartifacts.buy{value: PRICE}(harrys, 1);
        vm.prank(harry);
        chartifacts.collect();
        vm.prank(harry);
        vm.expectRevert("nothing is owed to you");
        chartifacts.collect();
    }

    function testCollectingTwiceInOneGoGetsPaidOnce() public {
        GreedyWallet greedy = new GreedyWallet(chartifacts);
        vm.prank(band);
        uint256 id = chartifacts.list("August", "Maddie Denton", CUT, "", 100, PRICE, 50, bytes32(0));
        vm.prank(band);
        chartifacts.setPickerWallet(id, address(greedy));

        vm.prank(fan);
        chartifacts.buy{value: 10 * PRICE}(id, 10);
        // Somebody else's money is in the contract too.
        vm.prank(otherFan);
        chartifacts.buy{value: 10 * PRICE}(harrys, 10);

        greedy.collect();
        assertEq(address(greedy).balance, 5 * PRICE);
        assertEq(greedy.timesPaid(), 1);
        assertEq(chartifacts.owed(harry), 4 * PRICE);
        assertEq(address(chartifacts).balance, 15 * PRICE);
    }

    // ---- handing over ----

    function testHandingOver() public {
        vm.prank(fan);
        chartifacts.buy{value: PRICE}(kyles, 1);

        vm.prank(band);
        chartifacts.handOver(otherFan);
        assertEq(chartifacts.band(), otherFan);

        vm.prank(band);
        vm.expectRevert("only the band can do this");
        chartifacts.setPrice(harrys, 1);

        // What the old address earned is still its to collect.
        vm.prank(band);
        chartifacts.collect();
        assertEq(band.balance, PRICE);

        vm.prank(otherFan);
        chartifacts.setPrice(harrys, 1);
    }

    function testHandOverNeedsAnAddressAndTheBand() public {
        vm.prank(band);
        vm.expectRevert("the band needs an address");
        chartifacts.handOver(address(0));
        vm.prank(stranger);
        vm.expectRevert("only the band can do this");
        chartifacts.handOver(stranger);
    }

    function testOnlyTheBandSetsTheMetadataUri() public {
        vm.prank(stranger);
        vm.expectRevert("only the band can do this");
        chartifacts.setMetadataUri("https://example.invalid/evil/{id}.json");
        vm.prank(band);
        chartifacts.setMetadataUri("https://example.invalid/new/{id}.json");
        assertEq(chartifacts.uri(0), "https://example.invalid/new/{id}.json");
    }

    // ---- the books always balance ----

    function testFuzzTheBooksBalance(uint8 a, uint8 b, uint8 percent, uint64 price) public {
        uint256 pct = bound(percent, 0, 100);
        uint256 p = bound(price, 0, 10 ether);
        uint256 first = bound(a, 1, 60);
        uint256 second = bound(b, 1, 60);

        vm.prank(band);
        uint256 id = chartifacts.list("Paint Exchange", "Harry Clark", "cut", "", 100, p, pct, bytes32(0));
        vm.prank(band);
        chartifacts.setPickerWallet(id, harry);

        vm.deal(fan, first * p);
        vm.prank(fan);
        chartifacts.buy{value: first * p}(id, first);

        vm.deal(otherFan, second * p);
        vm.prank(otherFan);
        if (first + second > 100) {
            vm.expectRevert("not that many shares left");
            chartifacts.buy{value: second * p}(id, second);
            second = 0;
        } else {
            chartifacts.buy{value: second * p}(id, second);
        }

        uint256 paid = (first + second) * p;
        assertEq(chartifacts.owed(harry) + chartifacts.owed(band), paid);
        assertEq(address(chartifacts).balance, paid);
        assertEq(chartifacts.balanceOf(fan, id) + chartifacts.balanceOf(otherFan, id), first + second);
        assertEq(chartifacts.sharesLeft(id), 100 - first - second);
    }
}
