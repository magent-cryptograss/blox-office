// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/SetStone.sol";
import "../contracts/LiveSet.sol";


contract SetStoneTests is Test {
    SetStone stone_contract;

    function setUp() public {
        stone_contract = new SetStone(address(this), "https://justinholmes.com/setstones/");

        // let's add some test data to the setlist contract

        // Show1
        bytes32[] memory rabbitHashes = new bytes32[](4);
        rabbitHashes[0] = keccak256(abi.encodePacked("rabbit1"));
        rabbitHashes[1] = keccak256(abi.encodePacked("rabbit2"));
        rabbitHashes[2] = keccak256(abi.encodePacked("rabbit3"));
        rabbitHashes[3] = keccak256(abi.encodePacked("rabbit4"));

        uint8[] memory shapes = new uint8[](2);
        shapes[0] = 0;
        shapes[1] = 1;

        stone_contract.makeShowAvailableForStoneMinting(
            {artist_id: 0,
                blockheight: 420,
                rabbitHashes: rabbitHashes,
                numberOfSets: 2,
                shapesBySetNumber: shapes, // empty shapes array, we will add them later
                stonePrice: 0.5 ether
            });

        // Show2
        bytes32[] memory rabbitHashes2 = new bytes32[](4);
        rabbitHashes2[0] = keccak256(abi.encodePacked("rabbit5"));
        rabbitHashes2[1] = keccak256(abi.encodePacked("rabbit6"));
        rabbitHashes2[2] = keccak256(abi.encodePacked("rabbit7"));
        rabbitHashes2[3] = keccak256(abi.encodePacked("rabbit8"));

        uint8[] memory shapes2 = new uint8[](2);
        shapes2[0] = 2;
        shapes2[1] = 3;

        stone_contract.makeShowAvailableForStoneMinting(
            {artist_id: 0,
                blockheight: 421,
                rabbitHashes: rabbitHashes2,
                numberOfSets: 2,
                shapesBySetNumber: shapes2, // empty shapes array, we will add them later
                stonePrice: 0.5 ether
            });

    }

    function test_mint_stones() public {
        uint16 artistId = 0;
        uint64 blockHeight = 420;

        vm.deal(address(this), 10 ether);

        // mint 2 stones for the same set
        stone_contract.mintStone{value: 0.5 ether}(
            address(this), artistId, blockHeight, 0,
            0, 1, 2, "crystalized", 0, "rabbit1"
        );

        stone_contract.mintStone{value: 1 ether}(
            address(this), artistId, blockHeight, 0,
            4, 5, 6, "crystalized stone 2", 1, "rabbit2"
        );

        assertEq(address(stone_contract).balance, 1.5 ether);

        uint256[] memory stoneIds = stone_contract.getStonesBySetId(artistId, blockHeight, 0);
        assertEq(stoneIds.length, 2);

        // Verify stone 1 attributes in isolated scope
        {
            SetStone.StoneColor memory color = stone_contract.getStoneColor(stoneIds[0]);
            assertEq(color.color1, 0);
            assertEq(color.color2, 1);
            assertEq(color.color3, 2);
            assertEq(stone_contract.getCrystalizationMsg(stoneIds[0]), "crystalized");
            assertEq(stone_contract.getPaidAmountWei(stoneIds[0]), 0.5 ether);
            assertEq(stone_contract.getFavoriteSong(stoneIds[0]), 0);
        }

        // Verify stone 2 attributes in isolated scope
        {
            SetStone.StoneColor memory color = stone_contract.getStoneColor(stoneIds[1]);
            assertEq(color.color1, 4);
            assertEq(color.color2, 5);
            assertEq(color.color3, 6);
            assertEq(stone_contract.getCrystalizationMsg(stoneIds[1]), "crystalized stone 2");
            assertEq(stone_contract.getPaidAmountWei(stoneIds[1]), 1 ether);
            assertEq(stone_contract.getFavoriteSong(stoneIds[1]), 1);
        }

        // check that the NFT has been properly minted
        assertEq(stone_contract.ownerOf(0), address(this));
        assertEq(stone_contract.ownerOf(1), address(this));
        assertEq(stone_contract.balanceOf(address(this)), 2);
        assertEq(stone_contract.tokenOfOwnerByIndex(address(this), 0), 0);
        assertEq(stone_contract.tokenOfOwnerByIndex(address(this), 1), 1);

        // check that Stone with non-existing tokenId is an uninitialized Stone struct
        {
            SetStone.StoneColor memory color = stone_contract.getStoneColor(1234);
            assertEq(color.color1, 0);
            assertEq(color.color2, 0);
            assertEq(color.color3, 0);
        }

        // mint one more stone for the second set
        stone_contract.mintStone{value: 1 ether}(
            address(this), artistId, blockHeight, 1,
            7, 8, 9, "crystalized", 2, "rabbit3"
        );

        // mint stone for the second show
        stone_contract.mintStone{value: 1 ether}(
            address(this), artistId, blockHeight + 1, 0,
            7, 7, 7, "crystalized", 3, "rabbit5"
        );

        assertEq(stone_contract.numberOfStonesMinted(), 4);
        assertEq(stone_contract.balanceOf(address(this)), 4);
    }


    function test_mint_stone_invalid_rabbit() public {
        // check that the minting reverts when given invalid secret rabbit
        vm.expectRevert("Invalid secret rabbit");
        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            420,
            0, // order
            0, // color
            1, // color
            2, // color
            "crystalized", // crystalization text
            0, // favorite song
            "invalid_rabbit" // invalid rabbit secret
        );

        assertEq(stone_contract.numberOfStonesMinted(), 0);
    }

    function test_mint_stone_invalid_set() public {
        vm.expectRevert("Set does not exist");
        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            420,
            2, // order
            0, // color1
            1, // color2
            2, // color3
            "crystalized",
            0, // favorite song
            "rabbit1"
        );

        // check that the minting reverts when given invalid set
        vm.expectRevert("Set does not exist");
        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            571, // non-existing LiveSet (0, 571)
            0,
            0, // color1
            1, // color2
            2, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit1" // rabbit secret
        );
    }


    function test_valid_color() public {

        // check that the minting reverts when given invalid color

        // minting first stone is just fine
        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            420,
            0, // order
            0, // color1
            1, // color2
            2, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit1" // rabbit secret
        );

        vm.expectRevert("Color already taken for this set");
        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            420,
            0, // order
            0, // color1
            1, // color2
            2, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit2" // rabbit secret
        );

    }

    function test_only_one_stone_per_secret_rabbit() public {
        // check that the minting reverts when given invalid secret rabbit
        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            420,
            0, // order
            0, // color1
            1, // color2
            2, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit1" // rabbit secret
        );

        vm.expectRevert("Invalid secret rabbit");
        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            420,
            0, // order
            1, // color1
            2, // color2
            3, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit1" // rabbit secret
        );
    }

    function test_check_token_uri() public {
        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            420,
            0, // order
            1, // color1
            2, // color2
            3, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit1" // rabbit secret
        );

        stone_contract.mintStone{value: 1 ether}(
            address(this),
            0,
            421,
            1, // order
            0, // color1
            1, // color2
            2, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit7" // rabbit secret
        );

        // Check the token URI of the minted stone
        string memory expectedTokenURI = "https://justinholmes.com/setstones/0";
        uint256 tokenID = 0;
        string memory actualTokenURI = stone_contract.tokenURI(tokenID);
        assertEq(actualTokenURI, expectedTokenURI, "Token URI does not match the expected value");


        expectedTokenURI = "https://justinholmes.com/setstones/1";
        tokenID = 1;
        actualTokenURI = stone_contract.tokenURI(tokenID);
        assertEq(actualTokenURI, expectedTokenURI, "Token URI does not match the expected value");
    }

    function test_paid_too_little_for_a_setstone() public {
        vm.expectRevert("Paid too little ETH for a setstone");
        stone_contract.mintStone{value: 0.1 ether}(
            address(this),
            0,
            420,
            0, // order
            1, // color1
            2, // color2
            3, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit1" // rabbit secret
        );
    }

    function test_get_show_data() public {
        // Act
        (bytes32 showBytes1, uint8 numberOfSets1, uint256 stonePrice1, bytes32[] memory rabbitHashes1, uint8[] memory setShapeBySetId1) = stone_contract.getShowData(0, 420);
        (bytes32 showBytes2, uint8 numberOfSets2, uint256 stonePrice2, bytes32[] memory rabbitHashes2, uint8[] memory setShapeBySetId2) = stone_contract.getShowData(0, 421);

        // Assert for Show1
        assertEq(numberOfSets1, 2, "Show1 number of sets does not match");
        assertEq(stonePrice1, 0.5 ether, "Show1 stone price does not match");
        assertEq(setShapeBySetId1.length, 2, "Show1 number of set shapes does not match");

        // Assert for Show2
        assertEq(numberOfSets2, 2, "Show2 number of sets does not match");
        assertEq(stonePrice2, 0.5 ether, "Show2 stone price does not match");
        assertEq(setShapeBySetId2.length, 2, "Show2 number of set shapes does not match");

        assertEq(rabbitHashes1.length, 4, "Show1 number of rabbit hashes does not match");
        assertEq(rabbitHashes2.length, 4, "Show2 number of rabbit hashes does not match");
    }

    function test_mint_stone_for_free() public {
        stone_contract.mintStoneForFree(
            address(this),
            0,
            420,
            0, // order
            0, // color1
            1, // color2
            2, // color3
            "crystalized", // crystalization text
            0, // favorite song
            "rabbit1" // rabbit secret
        );

        // check that the stone has the correct attributes
        uint256[] memory stoneIds = stone_contract.getStonesBySetId(0, 420, 0);

        assertEq(stoneIds.length, 1);
        SetStone.StoneColor memory stone1_color = stone_contract.getStoneColor(stoneIds[0]);
        string memory stone1_crystalization = stone_contract.getCrystalizationMsg(stoneIds[0]);
        uint256 stone1_paidAmountWei = stone_contract.getPaidAmountWei(stoneIds[0]);

        assertEq(stone1_color.color1, 0);
        assertEq(stone1_color.color2, 1);
        assertEq(stone1_color.color3, 2);
        assertEq(stone1_crystalization, "crystalized");
        assertEq(stone1_paidAmountWei, 0 ether);

        assertEq(stone1_color.color1, 0, "Minted stone color1 does not match");
        assertEq(stone1_color.color2, 1, "Minted stone color2 does not match");
        assertEq(stone1_color.color3, 2, "Minted stone color3 does not match");
        assertEq(stone1_crystalization, "crystalized", "Minted stone crystalization does not match");

    }

    function test_mint_stone_minimal() public {

        vm.deal(address(this), 10 ether);
        stone_contract.mintStone{value: 0.5 ether}(
            address(this),
            0, // artist id
            420, // blockheight
            0, // order
            0, // color1
            1, // color2
            2, // color3
            "", // crystalization text
            0, // favorite song
            "rabbit1" // rabbit secret
        );
    }
}