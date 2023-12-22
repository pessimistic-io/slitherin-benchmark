// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC721Holder.sol";
import "./IPlanckCat.sol";

contract PlanckCatMinter is ERC721Holder {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // planck cat NFT contract
    address public immutable pcd;

    // whether id is claimable by address
    mapping(uint256 => mapping(address => bool)) public claimable;
    // ids that have been escrowed
    mapping(address => uint256[]) public escrowed;
    // number remaining to be claimed
    mapping(address => uint256) public count;

    // events
    event Mint(address indexed to, uint256 id);
    event Claim(address indexed by, uint256 id);

    constructor(address _pcd) {
        pcd = _pcd;
    }

    modifier onlyMinter() {
        require(IPlanckCat(pcd).hasRole(MINTER_ROLE, msg.sender), "!minter");
        _;
    }

    /// @notice bulk mint new planck cats for claiming
    /// @dev mints to this planck cat minter contract first to avoid security
    /// @dev issues with ERC721 call back. After all are minted,
    /// @dev users can call claim() function. Technically the callback
    /// @dev shouldn't affect us given the onlyMinter modifier, but still.
    function mintBatch(uint256 currentId, address[] memory tos) external onlyMinter {
        require(isCurrentId(currentId), "!currentId");

        // loop through and safe mint to this address. track who
        // can claim which minted NFT thru claimable
        address _pcd = pcd;
        for (uint256 i = 0; i < tos.length; i++) {
            address to = tos[i];

            // mark as claimable and record escrowed id
            claimable[currentId][to] = true;
            escrowed[to].push(currentId);
            count[to]++;

            // emit mint event
            emit Mint(to, currentId);

            // increment current id counter
            currentId++;

            // mint to this address
            IPlanckCat(_pcd).safeMint(address(this));
        }
    }

    /// @notice bulk mint new custom planck cats for claiming
    /// @dev mints to this planck cat minter contract first to avoid security
    /// @dev issues with ERC721 call back. After all are minted,
    /// @dev users can call claim() function. Technically the callback
    /// @dev shouldn't affect us given the onlyMinter modifier, but still.
    function mintCustomBatch(
        uint256 currentId,
        address[] memory tos,
        string[] memory uris
    ) external onlyMinter {
        require(tos.length == uris.length, "tos != uris");
        require(isCurrentId(currentId), "!currentId");

        // loop through and safe mint to this address. track who
        // can claim which minted NFT thru claimable
        address _pcd = pcd;
        for (uint256 i = 0; i < tos.length; i++) {
            address to = tos[i];
            string memory uri = uris[i];

            // mark as claimable and record escrowed id
            claimable[currentId][to] = true;
            escrowed[to].push(currentId);
            count[to]++;

            // emit mint event
            emit Mint(to, currentId);

            // increment current id counter
            currentId++;

            // mint to this address
            IPlanckCat(_pcd).safeMintCustom(address(this), uri);
        }
    }

    /// @notice claim planck cat by ID
    function claim(uint256 id) external {
        address _pcd = pcd;

        // check can actually claim id
        require(claimable[id][msg.sender], "!claimable");

        // mark escrowed as claimed
        claimable[id][msg.sender] = false;
        count[msg.sender]--;

        // emit claim event
        emit Claim(msg.sender, id);

        // transfer escrowed to msg.sender
        IPlanckCat(_pcd).safeTransferFrom(address(this), msg.sender, id, "");
    }

    /// @notice check whether currentId is the ID of the next cat to be minted
    /// @dev IPlanckCat(_pcd)_tokenIdCounter.current() == currentId
    function isCurrentId(uint256 currentId) public view returns (bool) {
        address _pcd = pcd;

        // Gameplan: tokenURI(currentId) should revert on call to PCD BUT
        // tokenURI(currentId-1) should not IF isCurrentId(currentId) == true
        string memory nonexistentReason = "ERC721Metadata: URI query for nonexistent token";
        try IPlanckCat(_pcd).tokenURI(currentId) returns (string memory) {
            // if URI already exists, then not the current id
            return false;
        } catch Error(string memory reason) {
            if (currentId == 0) {
                return true;
            } else if (keccak256(bytes(reason)) == keccak256(bytes(nonexistentReason))) {
                // currentId hasn't been minted yet. Now check that
                // currentId - 1 has been minted, so we know currentId is the
                // next ID
                try IPlanckCat(_pcd).tokenURI(currentId - 1) returns (string memory) {
                    // last minted ID was currentId-1, so currentId is actually the current id
                    return true;
                } catch {}
            }
        }
        return false;
    }

    /// @notice returns IDs that can still be claimed for by
    function canClaim(address by) external view returns (uint256[] memory can_) {
        uint256[] memory ids = escrowed[by];
        can_ = new uint256[](count[by]);

        uint256 idx;
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            if (claimable[id][by]) {
                can_[idx] = id;
                idx++;
            }
        }
    }
}

