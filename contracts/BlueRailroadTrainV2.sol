// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title IBlueRailroadV1
 * @notice Interface for reading data from the V1 Blue Railroad contract
 */
interface IBlueRailroadV1 is IERC721 {
    function tokenIdToSongId(uint32 tokenId) external view returns (uint32);
    function tokenIdToDate(uint32 tokenId) external view returns (uint32);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/**
 * @title BlueRailroadTrainV2
 * @notice Blue Railroad NFT contract for exercise challenge tokens
 * @dev Mints tokens representing completed exercises to Tony Rice's Manzanita album.
 *      Song IDs correspond to track numbers on Manzanita (1979):
 *      - Track 5: Nine Pound Hammer (Pushups)
 *      - Track 7: Blue Railroad Train (Squats)
 *      - Track 8: Ginseng Sullivan (Army Crawls)
 *
 *      V2 changes from V1:
 *      - Uses Ethereum blockheight instead of calendar date for temporal anchoring
 *      - Adds setBaseURI for future domain changes
 *      - Adds trustless migration from V1 via migrateFromV1()
 */
contract BlueRailroadTrainV2 is ERC721, ERC721Enumerable, ERC721Burnable, Ownable {
    using Strings for uint256;
    uint32 private _nextTokenId;

    /// @notice Maps token ID to Manzanita track number (5, 7, or 8)
    mapping(uint32 => uint32) public tokenIdToSongId;

    /// @notice Maps token ID to Ethereum mainnet blockheight when exercise was performed
    mapping(uint32 => uint256) public tokenIdToBlockheight;

    /// @notice Maps token ID to IPFS video content hash (CIDv0 digest, 32 bytes)
    mapping(uint32 => bytes32) public tokenIdToVideoHash;

    /// @notice Tracks which V1 token IDs have been migrated (prevents double-migration)
    /// @dev Only 5 V1 tokens exist (IDs 0-4), so uint32 is plenty
    mapping(uint32 => bool) public v1TokenMigrated;

    string private _baseTokenURI;

    /// @notice The V1 contract address on Optimism
    IBlueRailroadV1 public immutable v1Contract;

    /// @notice Dead address where V1 tokens are sent during migration
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Emitted when a token is migrated from V1 to V2
    /// @dev v1TokenId == v2TokenId (we preserve the token ID during migration)
    event TokenMigrated(uint32 indexed tokenId, address indexed holder);

    constructor(address initialOwner, address _v1Contract)
        ERC721("Blue Railroad Train Squats", "TONY")
        Ownable(initialOwner)
    {
        v1Contract = IBlueRailroadV1(_v1Contract);
    }

    /**
     * @notice Migrate a token from V1 to V2 (trustless)
     * @dev Caller must own the V1 token and have approved this contract to transfer it.
     *      The V1 token is sent to the burn address, and a V2 token with the SAME ID is minted.
     *      Caller provides corrected metadata (songId, blockheight, videoHash) since V1 data may be wrong.
     * @param v1TokenId The token ID on the V1 contract to migrate (V2 will use same ID)
     * @param songId Corrected Manzanita track number (5=Pushups, 7=Squats, 8=Army Crawls)
     * @param blockheight Ethereum mainnet blockheight when the exercise was performed
     * @param videoHash IPFS CIDv0 digest (32 bytes) of the exercise video
     */
    function migrateFromV1(uint32 v1TokenId, uint32 songId, uint256 blockheight, bytes32 videoHash) external {
        require(!v1TokenMigrated[v1TokenId], "Token already migrated");
        require(v1Contract.ownerOf(v1TokenId) == msg.sender, "Caller does not own V1 token");

        // Mark as migrated before external call (reentrancy protection)
        v1TokenMigrated[v1TokenId] = true;

        // Transfer V1 token to burn address (caller must have approved this contract)
        v1Contract.transferFrom(msg.sender, BURN_ADDRESS, v1TokenId);

        // Mint V2 token with same ID as V1 token
        tokenIdToSongId[v1TokenId] = songId;
        tokenIdToBlockheight[v1TokenId] = blockheight;
        tokenIdToVideoHash[v1TokenId] = videoHash;
        _safeMint(msg.sender, v1TokenId);

        // Update _nextTokenId if needed (so new mints don't collide)
        if (v1TokenId >= _nextTokenId) {
            _nextTokenId = v1TokenId + 1;
        }

        emit TokenMigrated(v1TokenId, msg.sender);
    }

    /**
     * @notice Mint a new Blue Railroad token (owner only, for new exercises)
     * @param recipient Address to receive the token
     * @param songId Manzanita track number (5=Pushups, 7=Squats, 8=Army Crawls)
     * @param blockheight Ethereum mainnet blockheight when the exercise was performed
     * @param videoHash IPFS CIDv0 digest (32 bytes) of the exercise video
     */
    function issueTony(address recipient, uint32 songId, uint256 blockheight, bytes32 videoHash) public onlyOwner {
        uint32 tokenId = _nextTokenId++;
        tokenIdToSongId[tokenId] = songId;
        tokenIdToBlockheight[tokenId] = blockheight;
        tokenIdToVideoHash[tokenId] = videoHash;
        _safeMint(recipient, tokenId);
    }

    /**
     * @notice Update the base URI for all tokens
     * @dev Useful if the domain or IPFS gateway changes. Only callable by owner.
     * @param newBaseURI The new base URI to prepend to token URIs
     */
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    /**
     * @notice Returns the base URI for token metadata
     * @dev Overrides ERC721's _baseURI to use our configurable base
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    // =========================================================================
    // Required overrides for multiple inheritance
    // =========================================================================
    // Solidity requires explicit overrides when a contract inherits from multiple
    // parents that define the same function. These all just delegate to super.

    /**
     * @dev Override required because both ERC721 and ERC721Enumerable define _update.
     *      Called on every transfer (including mint and burn) to update ownership tracking.
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Override required because both ERC721 and ERC721Enumerable define _increaseBalance.
     *      Called when minting to update the owner's token count.
     */
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    /**
     * @dev Returns the full URI for a token's metadata.
     *      Concatenates baseURI + tokenId (e.g., "https://cryptograss.live/meta/bluerailroad/" + "0")
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        _requireOwned(tokenId);
        return string.concat(_baseTokenURI, tokenId.toString());
    }

    /**
     * @dev Override required because ERC721 and ERC721Enumerable both define supportsInterface.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
