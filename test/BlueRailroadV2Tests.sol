// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/BlueRailroadTrainV2.sol";

/**
 * @title MockV1Contract
 * @notice Mock V1 contract for testing migration functionality
 */
contract MockV1Contract is ERC721 {
    mapping(uint32 => uint32) public tokenIdToSongId;
    mapping(uint32 => uint32) public tokenIdToDate;

    constructor() ERC721("Blue Railroad Train V1", "TONY") {}

    function mint(address to, uint256 tokenId, uint32 songId, uint32 date) external {
        _mint(to, tokenId);
        tokenIdToSongId[uint32(tokenId)] = songId;
        tokenIdToDate[uint32(tokenId)] = date;
    }
}

contract BlueRailroadV2Tests is Test {
    BlueRailroadTrainV2 blueRailroad;
    MockV1Contract v1Contract;
    address owner;
    address alice;
    address bob;

    // Manzanita track numbers
    uint8 constant PUSHUPS = 5;      // Nine Pound Hammer
    uint8 constant SQUATS = 7;       // Blue Railroad Train
    uint8 constant ARMY_CRAWLS = 8;  // Ginseng Sullivan

    // Sample blockheights (Ethereum mainnet)
    uint256 constant BLOCK_JAN_2024 = 19000000;
    uint256 constant BLOCK_JAN_2026 = 21500000;

    // Sample IPFS video hashes (CIDv0 digest portion)
    bytes32 constant VIDEO_HASH_1 = keccak256("video1");
    bytes32 constant VIDEO_HASH_2 = keccak256("video2");
    bytes32 constant VIDEO_HASH_3 = keccak256("video3");

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy mock V1 contract first
        v1Contract = new MockV1Contract();

        // Deploy V2 with reference to V1
        blueRailroad = new BlueRailroadTrainV2(owner, address(v1Contract));
    }

    // ============ Minting Tests ============

    function test_mint_token_with_correct_metadata() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, VIDEO_HASH_1);

        assertEq(blueRailroad.ownerOf(0), alice);
        assertEq(blueRailroad.tokenIdToSongId(0), SQUATS);
        assertEq(blueRailroad.tokenIdToBlockheight(0), BLOCK_JAN_2026);
        assertEq(blueRailroad.tokenIdToVideoHash(0), VIDEO_HASH_1);
        assertEq(blueRailroad.totalSupply(), 1);
    }

    function test_mint_multiple_tokens_increments_id() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);
        blueRailroad.issueTony(bob, PUSHUPS, BLOCK_JAN_2024 + 1000, VIDEO_HASH_2);
        blueRailroad.issueTony(alice, ARMY_CRAWLS, BLOCK_JAN_2026, VIDEO_HASH_3);

        assertEq(blueRailroad.totalSupply(), 3);
        assertEq(blueRailroad.ownerOf(0), alice);
        assertEq(blueRailroad.ownerOf(1), bob);
        assertEq(blueRailroad.ownerOf(2), alice);

        assertEq(blueRailroad.tokenIdToSongId(0), SQUATS);
        assertEq(blueRailroad.tokenIdToSongId(1), PUSHUPS);
        assertEq(blueRailroad.tokenIdToSongId(2), ARMY_CRAWLS);
    }

    function test_only_owner_can_mint() public {
        vm.prank(alice);
        vm.expectRevert();
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, VIDEO_HASH_1);
    }

    // ============ Base URI Tests ============

    function test_owner_can_set_base_uri() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, VIDEO_HASH_1);

        // Initially no base URI, tokenURI is just the ID
        assertEq(blueRailroad.tokenURI(0), "0");

        // Set base URI
        blueRailroad.setBaseURI("https://cryptograss.live/meta/bluerailroad/");

        // Now token URI includes base
        assertEq(blueRailroad.tokenURI(0), "https://cryptograss.live/meta/bluerailroad/0");
    }

    function test_non_owner_cannot_set_base_uri() public {
        vm.prank(alice);
        vm.expectRevert();
        blueRailroad.setBaseURI("https://evil.com/");
    }

    // ============ ERC721 Standard Tests ============

    function test_token_holder_can_transfer() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, VIDEO_HASH_1);

        vm.prank(alice);
        blueRailroad.transferFrom(alice, bob, 0);

        assertEq(blueRailroad.ownerOf(0), bob);
    }

    function test_token_holder_can_burn() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, VIDEO_HASH_1);

        assertEq(blueRailroad.totalSupply(), 1);

        vm.prank(alice);
        blueRailroad.burn(0);

        assertEq(blueRailroad.totalSupply(), 0);
    }

    function test_enumerable_functions_work() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);
        blueRailroad.issueTony(alice, PUSHUPS, BLOCK_JAN_2024 + 500, VIDEO_HASH_2);
        blueRailroad.issueTony(bob, ARMY_CRAWLS, BLOCK_JAN_2026, VIDEO_HASH_3);

        assertEq(blueRailroad.balanceOf(alice), 2);
        assertEq(blueRailroad.balanceOf(bob), 1);

        assertEq(blueRailroad.tokenOfOwnerByIndex(alice, 0), 0);
        assertEq(blueRailroad.tokenOfOwnerByIndex(alice, 1), 1);
        assertEq(blueRailroad.tokenOfOwnerByIndex(bob, 0), 2);

        assertEq(blueRailroad.tokenByIndex(0), 0);
        assertEq(blueRailroad.tokenByIndex(1), 1);
        assertEq(blueRailroad.tokenByIndex(2), 2);
    }

    // ============ Interface Support Tests ============

    function test_supports_erc721_interfaces() public view {
        // ERC721
        assertTrue(blueRailroad.supportsInterface(0x80ac58cd));
        // ERC721Metadata
        assertTrue(blueRailroad.supportsInterface(0x5b5e139f));
        // ERC721Enumerable
        assertTrue(blueRailroad.supportsInterface(0x780e9d63));
        // ERC165
        assertTrue(blueRailroad.supportsInterface(0x01ffc9a7));
    }

    // ============ Contract Metadata Tests ============

    function test_name_and_symbol() public view {
        assertEq(blueRailroad.name(), "Blue Railroad Train Squats");
        assertEq(blueRailroad.symbol(), "TONY");
    }

    // ============ V1 Migration Tests ============

    function test_migrate_from_v1_success() public {
        // Mint a V1 token to alice
        v1Contract.mint(alice, 0, PUSHUPS, 20240115);

        // Alice approves V2 contract to transfer her V1 token
        vm.prank(alice);
        v1Contract.approve(address(blueRailroad), 0);

        // Alice migrates with corrected metadata
        vm.prank(alice);
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);

        // V1 token should be at burn address
        assertEq(v1Contract.ownerOf(0), blueRailroad.BURN_ADDRESS());

        // V2 token should be minted to alice with corrected data
        assertEq(blueRailroad.ownerOf(0), alice);
        assertEq(blueRailroad.tokenIdToSongId(0), SQUATS);
        assertEq(blueRailroad.tokenIdToBlockheight(0), BLOCK_JAN_2024);
        assertEq(blueRailroad.tokenIdToVideoHash(0), VIDEO_HASH_1);
    }

    function test_migrate_from_v1_not_owner_reverts() public {
        // Mint a V1 token to alice
        v1Contract.mint(alice, 0, PUSHUPS, 20240115);

        // Bob tries to migrate alice's token
        vm.prank(bob);
        vm.expectRevert("Caller does not own V1 token");
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);
    }

    function test_migrate_from_v1_double_migration_reverts() public {
        // Mint a V1 token to alice
        v1Contract.mint(alice, 0, PUSHUPS, 20240115);

        // Alice approves and migrates
        vm.startPrank(alice);
        v1Contract.approve(address(blueRailroad), 0);
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);
        vm.stopPrank();

        // Try to migrate again - fails because V1 token is now owned by burn address, not alice
        vm.prank(alice);
        vm.expectRevert("Caller does not own V1 token");
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);
    }

    function test_migrate_multiple_tokens() public {
        // Mint multiple V1 tokens
        v1Contract.mint(alice, 0, PUSHUPS, 20240115);
        v1Contract.mint(alice, 1, PUSHUPS, 20240116);
        v1Contract.mint(bob, 2, PUSHUPS, 20240117);

        // Alice migrates her tokens
        vm.startPrank(alice);
        v1Contract.approve(address(blueRailroad), 0);
        v1Contract.approve(address(blueRailroad), 1);
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);
        blueRailroad.migrateFromV1(1, SQUATS, BLOCK_JAN_2024 + 1000, VIDEO_HASH_2);
        vm.stopPrank();

        // Bob migrates his token
        vm.startPrank(bob);
        v1Contract.approve(address(blueRailroad), 2);
        blueRailroad.migrateFromV1(2, ARMY_CRAWLS, BLOCK_JAN_2026, VIDEO_HASH_3);
        vm.stopPrank();

        // Check V2 state
        assertEq(blueRailroad.totalSupply(), 3);
        assertEq(blueRailroad.balanceOf(alice), 2);
        assertEq(blueRailroad.balanceOf(bob), 1);
        assertEq(blueRailroad.ownerOf(0), alice);
        assertEq(blueRailroad.ownerOf(1), alice);
        assertEq(blueRailroad.ownerOf(2), bob);
    }

    function test_v1_contract_address_stored() public view {
        assertEq(address(blueRailroad.v1Contract()), address(v1Contract));
    }

    function test_new_mints_after_migration_dont_collide() public {
        // Migrate V1 tokens 0 and 2 (skipping 1)
        v1Contract.mint(alice, 0, PUSHUPS, 20240115);
        v1Contract.mint(bob, 2, PUSHUPS, 20240117);

        vm.prank(alice);
        v1Contract.approve(address(blueRailroad), 0);
        vm.prank(alice);
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);

        vm.prank(bob);
        v1Contract.approve(address(blueRailroad), 2);
        vm.prank(bob);
        blueRailroad.migrateFromV1(2, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_2);

        // Now mint a new token - should get ID 3 (after highest migrated ID)
        blueRailroad.issueTony(alice, ARMY_CRAWLS, BLOCK_JAN_2026, VIDEO_HASH_3);

        // Verify token IDs: 0 (migrated), 2 (migrated), 3 (new)
        assertEq(blueRailroad.ownerOf(0), alice);
        assertEq(blueRailroad.ownerOf(2), bob);
        assertEq(blueRailroad.ownerOf(3), alice);
        assertEq(blueRailroad.totalSupply(), 3);
    }

    function test_migration_preserves_token_id() public {
        // Migrate token ID 4 specifically
        v1Contract.mint(alice, 4, PUSHUPS, 20240115);

        vm.prank(alice);
        v1Contract.approve(address(blueRailroad), 4);
        vm.prank(alice);
        blueRailroad.migrateFromV1(4, SQUATS, BLOCK_JAN_2024, VIDEO_HASH_1);

        // V2 token should have same ID as V1 token
        assertEq(blueRailroad.ownerOf(4), alice);

        // Next new mint should be ID 5
        blueRailroad.issueTony(bob, PUSHUPS, BLOCK_JAN_2026, VIDEO_HASH_2);
        assertEq(blueRailroad.ownerOf(5), bob);
    }

    function test_token_uri_format() public {
        blueRailroad.setBaseURI("https://cryptograss.live/meta/bluerailroad/");
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, VIDEO_HASH_1);
        blueRailroad.issueTony(bob, PUSHUPS, BLOCK_JAN_2026, VIDEO_HASH_2);

        assertEq(blueRailroad.tokenURI(0), "https://cryptograss.live/meta/bluerailroad/0");
        assertEq(blueRailroad.tokenURI(1), "https://cryptograss.live/meta/bluerailroad/1");
    }

    function test_video_hash_stored_correctly() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, VIDEO_HASH_1);
        blueRailroad.issueTony(bob, PUSHUPS, BLOCK_JAN_2024, VIDEO_HASH_2);

        assertEq(blueRailroad.tokenIdToVideoHash(0), VIDEO_HASH_1);
        assertEq(blueRailroad.tokenIdToVideoHash(1), VIDEO_HASH_2);
    }
}
