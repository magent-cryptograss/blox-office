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
    uint32 constant PUSHUPS = 5;      // Nine Pound Hammer
    uint32 constant SQUATS = 7;       // Blue Railroad Train
    uint32 constant ARMY_CRAWLS = 8;  // Ginseng Sullivan

    // Sample blockheights (Ethereum mainnet)
    uint256 constant BLOCK_JAN_2024 = 19000000;
    uint256 constant BLOCK_JAN_2026 = 21500000;

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
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, "ipfs://QmTest123");

        assertEq(blueRailroad.ownerOf(0), alice);
        assertEq(blueRailroad.tokenIdToSongId(0), SQUATS);
        assertEq(blueRailroad.tokenIdToBlockheight(0), BLOCK_JAN_2026);
        assertEq(blueRailroad.tokenURI(0), "ipfs://QmTest123");
        assertEq(blueRailroad.totalSupply(), 1);
    }

    function test_mint_multiple_tokens_increments_id() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2024, "ipfs://QmFirst");
        blueRailroad.issueTony(bob, PUSHUPS, BLOCK_JAN_2024 + 1000, "ipfs://QmSecond");
        blueRailroad.issueTony(alice, ARMY_CRAWLS, BLOCK_JAN_2026, "ipfs://QmThird");

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
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, "ipfs://QmTest");
    }

    // ============ Base URI Tests ============

    function test_owner_can_set_base_uri() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, "QmTest123");

        // Initially no base URI
        assertEq(blueRailroad.tokenURI(0), "QmTest123");

        // Set base URI
        blueRailroad.setBaseURI("ipfs://");

        // Now token URI includes base
        assertEq(blueRailroad.tokenURI(0), "ipfs://QmTest123");
    }

    function test_non_owner_cannot_set_base_uri() public {
        vm.prank(alice);
        vm.expectRevert();
        blueRailroad.setBaseURI("https://evil.com/");
    }

    // ============ ERC721 Standard Tests ============

    function test_token_holder_can_transfer() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, "ipfs://QmTest");

        vm.prank(alice);
        blueRailroad.transferFrom(alice, bob, 0);

        assertEq(blueRailroad.ownerOf(0), bob);
    }

    function test_token_holder_can_burn() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2026, "ipfs://QmTest");

        assertEq(blueRailroad.totalSupply(), 1);

        vm.prank(alice);
        blueRailroad.burn(0);

        assertEq(blueRailroad.totalSupply(), 0);
    }

    function test_enumerable_functions_work() public {
        blueRailroad.issueTony(alice, SQUATS, BLOCK_JAN_2024, "ipfs://Qm1");
        blueRailroad.issueTony(alice, PUSHUPS, BLOCK_JAN_2024 + 500, "ipfs://Qm2");
        blueRailroad.issueTony(bob, ARMY_CRAWLS, BLOCK_JAN_2026, "ipfs://Qm3");

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
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, "ipfs://QmCorrected");

        // V1 token should be at burn address
        assertEq(v1Contract.ownerOf(0), blueRailroad.BURN_ADDRESS());

        // V2 token should be minted to alice with corrected data
        assertEq(blueRailroad.ownerOf(0), alice);
        assertEq(blueRailroad.tokenIdToSongId(0), SQUATS);
        assertEq(blueRailroad.tokenIdToBlockheight(0), BLOCK_JAN_2024);
        assertEq(blueRailroad.tokenURI(0), "ipfs://QmCorrected");

        // Migration should be marked
        assertTrue(blueRailroad.v1TokenMigrated(0));
    }

    function test_migrate_from_v1_not_owner_reverts() public {
        // Mint a V1 token to alice
        v1Contract.mint(alice, 0, PUSHUPS, 20240115);

        // Bob tries to migrate alice's token
        vm.prank(bob);
        vm.expectRevert("Caller does not own V1 token");
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, "ipfs://QmStolen");
    }

    function test_migrate_from_v1_double_migration_reverts() public {
        // Mint a V1 token to alice
        v1Contract.mint(alice, 0, PUSHUPS, 20240115);

        // Alice approves and migrates
        vm.startPrank(alice);
        v1Contract.approve(address(blueRailroad), 0);
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, "ipfs://QmFirst");
        vm.stopPrank();

        // Now mint another V1 token with same ID to bob (simulating burn address transfer back - impossible in reality)
        // Instead, test that the mapping blocks re-migration even if someone got the token
        // The v1TokenMigrated mapping should prevent this

        // Try to migrate again (would fail anyway since token is at burn address, but mapping catches it first)
        vm.prank(alice);
        vm.expectRevert("Token already migrated");
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, "ipfs://QmSecond");
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
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, "ipfs://Qm0");
        blueRailroad.migrateFromV1(1, SQUATS, BLOCK_JAN_2024 + 1000, "ipfs://Qm1");
        vm.stopPrank();

        // Bob migrates his token
        vm.startPrank(bob);
        v1Contract.approve(address(blueRailroad), 2);
        blueRailroad.migrateFromV1(2, ARMY_CRAWLS, BLOCK_JAN_2026, "ipfs://Qm2");
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
        blueRailroad.migrateFromV1(0, SQUATS, BLOCK_JAN_2024, "ipfs://Qm0");

        vm.prank(bob);
        v1Contract.approve(address(blueRailroad), 2);
        vm.prank(bob);
        blueRailroad.migrateFromV1(2, SQUATS, BLOCK_JAN_2024, "ipfs://Qm2");

        // Now mint a new token - should get ID 3 (after highest migrated ID)
        blueRailroad.issueTony(alice, ARMY_CRAWLS, BLOCK_JAN_2026, "ipfs://QmNew");

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
        blueRailroad.migrateFromV1(4, SQUATS, BLOCK_JAN_2024, "ipfs://Qm4");

        // V2 token should have same ID as V1 token
        assertEq(blueRailroad.ownerOf(4), alice);
        assertTrue(blueRailroad.v1TokenMigrated(4));

        // Next new mint should be ID 5
        blueRailroad.issueTony(bob, PUSHUPS, BLOCK_JAN_2026, "ipfs://QmNext");
        assertEq(blueRailroad.ownerOf(5), bob);
    }
}
