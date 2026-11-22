// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// CHARTIFACTS
//
// A chartifact is one picker's chart for one recording: what Harry Clark
// played on "August", say. This contract keeps the list of chartifacts and
// who holds a piece of each.
//
// How it works, start to finish:
//
//   1. The band lists a chartifact and says how many SHARES it is split into
//      and what one share costs.
//   2. Anyone can buy shares. A share does not exist until somebody gets it.
//   3. The money is split on the spot between the picker and the band. It
//      waits in this contract until each of them collects it. A picker with
//      no wallet on file yet loses nothing: their cut is held until they do.
//   4. Your shares are yours. You can keep them, give them away, or sell them
//      anywhere, without asking the band.
//   5. Whoever gathers every share of a chartifact holds the whole thing.
//
// The share-keeping itself (who has how many, and moving them between people)
// is ERC-1155, a standard that wallets and marketplaces already understand.
// That part is OpenZeppelin's code, imported above. Everything below is ours.

contract Chartifacts is ERC1155 {
    string public constant name = "Chartifacts";

    // The band's address. Only the band can list chartifacts and change prices.
    address public band;

    struct Chartifact {
        string song;          // "August"
        string picker;        // "Harry Clark", as their page on PickiPedia is titled
        string cut;           // which recording: its Release id on PickiPedia
        string part;          // empty for the picker's whole chart; else "third A part",
                              // in the words the song's page on PickiPedia uses for
                              // it (there the field is called "section")
        uint256 shares;       // how many shares it is split into. Never changes.
        uint256 spokenFor;    // how many of those are bought, given, or set aside
        uint256 price;        // what one share costs from the band, in wei
        address pickerWallet; // where the picker's cut goes. Zero until they have one;
                              // until then their cut is held (see heldForPicker).
        uint256 pickerPercent; // the picker's cut of each sale, 0 to 100
        bytes32 paperSeal;    // for a chartifact with a paper chart: the hash of the
                              // secret written on the paper. Zero means no paper.
    }

    // Every chartifact, in the order listed. A chartifact's id is its place here.
    Chartifact[] public chartifacts;

    // Stops the same chart from being listed twice.
    mapping(bytes32 => bool) public alreadyListed;

    // Money waiting to be collected, by address.
    mapping(address => uint256) public owed;

    // The picker's cut of sales made before their wallet was on file, by
    // chartifact id. It waits here. Nobody can collect it, the band included,
    // until a wallet is recorded for that chartifact.
    mapping(uint256 => uint256) public heldForPicker;

    // Shares held for somebody who has no wallet yet. They hold a secret code;
    // the contract holds only the code's hash. See setAside and claim.
    struct Aside {
        uint256 id;
        uint256 shares;
    }
    mapping(bytes32 => Aside) public aside;

    event Listed(uint256 indexed id, string song, string picker, string cut, string part, uint256 shares, uint256 price);
    event PriceChanged(uint256 indexed id, uint256 price);
    event Bought(uint256 indexed id, address indexed buyer, uint256 shares, uint256 paid);
    event SetAside(uint256 indexed id, uint256 shares, bytes32 codeHash);
    event Collected(address indexed who, uint256 amount);

    modifier onlyBand() {
        require(msg.sender == band, "only the band can do this");
        _;
    }

    // A chartifact's id is its number in the list. Ask for a number that was
    // never listed and you get a sentence back.
    modifier mustExist(uint256 id) {
        require(id < chartifacts.length, "no chartifact by that number");
        _;
    }

    constructor(string memory metadataUri) ERC1155(metadataUri) {
        band = msg.sender;
    }

    // ---------------------------------------------------------------
    // The band lists a chartifact
    // ---------------------------------------------------------------

    function list(
        string memory song,
        string memory picker,
        string memory cut,
        string memory part,
        uint256 shares,
        uint256 price,
        uint256 pickerPercent,
        bytes32 paperSeal
    ) external onlyBand returns (uint256 id) {
        require(shares > 0, "a chartifact needs at least one share");
        require(pickerPercent <= 100, "a percent is 0 to 100");

        bytes32 key = keccak256(abi.encode(cut, picker, part));
        require(!alreadyListed[key], "this chart is already listed");
        alreadyListed[key] = true;

        id = chartifacts.length;
        Chartifact storage c = chartifacts.push();
        c.song = song;
        c.picker = picker;
        c.cut = cut;
        c.part = part;
        c.shares = shares;
        c.price = price;
        c.pickerPercent = pickerPercent;
        c.paperSeal = paperSeal;

        emit Listed(id, song, picker, cut, part, shares, price);
    }

    // The price of the shares nobody has yet. Shares already held are not touched.
    function setPrice(uint256 id, uint256 price) external onlyBand mustExist(id) {
        chartifacts[id].price = price;
        emit PriceChanged(id, price);
    }

    // The band records a picker's wallet here. Whatever was held for the
    // picker becomes theirs to collect, and their cut of every sale from then
    // on goes straight to the wallet.
    function setPickerWallet(uint256 id, address pickerWallet) external onlyBand mustExist(id) {
        chartifacts[id].pickerWallet = pickerWallet;
        if (pickerWallet != address(0)) {
            owed[pickerWallet] += heldForPicker[id];
            heldForPicker[id] = 0;
        }
    }

    // ---------------------------------------------------------------
    // Getting shares
    // ---------------------------------------------------------------

    // Buy shares with ether. Send exactly the price; the shares are yours in
    // the same transaction.
    function buy(uint256 id, uint256 shares) external payable mustExist(id) {
        Chartifact storage c = chartifacts[id];
        require(msg.value == c.price * shares, "send exactly the price");
        _speakFor(c, shares);

        uint256 pickersCut = (msg.value * c.pickerPercent) / 100;
        if (c.pickerWallet == address(0)) {
            heldForPicker[id] += pickersCut;
        } else {
            owed[c.pickerWallet] += pickersCut;
        }
        owed[band] += msg.value - pickersCut;

        _mint(msg.sender, id, shares, "");
        emit Bought(id, msg.sender, shares, msg.value);
    }

    // The band hands shares straight to somebody: a person who paid in
    // dollars, or a picker getting a piece of their own chart.
    function give(uint256 id, address to, uint256 shares) external onlyBand mustExist(id) {
        _speakFor(chartifacts[id], shares);
        _mint(to, id, shares, "");
    }

    // For somebody with no wallet yet. The band makes up a secret code, gives
    // the code to that person, and records only its hash here. The shares
    // wait, and nobody else can buy them.
    function setAside(uint256 id, uint256 shares, bytes32 codeHash) external onlyBand mustExist(id) {
        require(shares > 0, "set aside at least one share");
        require(aside[codeHash].shares == 0, "that code is already in use");
        _speakFor(chartifacts[id], shares);
        aside[codeHash] = Aside(id, shares);
        emit SetAside(id, shares, codeHash);
    }

    // Whoever knows the code sends the waiting shares to any address. A code
    // works once.
    function claim(string calldata code, address to) external {
        bytes32 codeHash = keccak256(bytes(code));
        Aside memory waiting = aside[codeHash];
        require(waiting.shares > 0, "no shares are waiting under that code");
        delete aside[codeHash];
        _mint(to, waiting.id, waiting.shares, "");
    }

    // Counts shares as spoken for, and refuses if there are not enough left.
    function _speakFor(Chartifact storage c, uint256 shares) private {
        require(c.spokenFor + shares <= c.shares, "not that many shares left");
        c.spokenFor += shares;
    }

    // ---------------------------------------------------------------
    // Collecting money
    // ---------------------------------------------------------------

    // Pickers and the band call this to take what sales have earned them.
    function collect() external {
        uint256 amount = owed[msg.sender];
        require(amount > 0, "nothing is owed to you");
        owed[msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "the payment did not go through");
        emit Collected(msg.sender, amount);
    }

    // ---------------------------------------------------------------
    // Looking things up
    // ---------------------------------------------------------------

    function count() external view returns (uint256) {
        return chartifacts.length;
    }

    function sharesLeft(uint256 id) external view mustExist(id) returns (uint256) {
        return chartifacts[id].shares - chartifacts[id].spokenFor;
    }

    // True when one address holds every share. For a chartifact with paper,
    // this is who the paper belongs to.
    function holdsAll(address who, uint256 id) external view mustExist(id) returns (bool) {
        return balanceOf(who, id) == chartifacts[id].shares;
    }

    // ---------------------------------------------------------------
    // Housekeeping
    // ---------------------------------------------------------------

    // The band moves to a new address. Money already owed to the old address
    // stays owed to the old address.
    function handOver(address newBand) external onlyBand {
        require(newBand != address(0), "the band needs an address");
        band = newBand;
    }

    // Where wallets and marketplaces look up a chartifact's picture and words.
    function setMetadataUri(string calldata metadataUri) external onlyBand {
        _setURI(metadataUri);
    }
}
