//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1155.sol";
import "./Mintable.sol";
import "./ClaimContext.sol";
import "./ERC1155Burnable.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";

/// @author NitroLeague.
contract DriverComponents is
    ERC1155,
    Mintable,
    ClaimContext,
    ReentrancyGuard,
    ERC1155Burnable,
    Pausable
{
    bool private _isMetaLocked;
    address private _trustedAllowlistContract;

    event SetAllowlistContract(address oldAllowlist, address newAllowlist);

    constructor(
        address forwarder,
        address minter,
        uint dailyLimit
    ) ERC1155("", forwarder) Mintable(dailyLimit) {
        setMinter(minter);
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Sets a new URI for all token types, by relying on the token type ID
     *
     * @param newuri base uri for tokens
     */
    function setURI(string memory newuri) public onlyOwner {
        require(!_isMetaLocked, "Metadata locked");
        _setURI(newuri);
    }

    /**
     * Get URI of token with given id.
     */
    function uri(uint256 _tokenid)
        public
        view
        override
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    ERC1155.uri(_tokenid),
                    Strings.toString(_tokenid),
                    ".json"
                )
            );
    }

    /**
     * @dev Mints a token to a wallet (called by owner)
     *
     * @param to address to mint to
     * @param id token id to be minted.
     */
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyOwner whenNotPaused {
        _mint(to, id, amount, data);
    }

    /**
     * @dev Mints a token to a winner against a context (called by minter)
     *
     * @param _context Race/Event address, Lootbox or blueprint ID.
     * @param _to address to mint to
     * @param id token id to be minted.
     */
    function mintGame(
        string calldata _context,
        address _to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyMinter whenNotPaused inLimit validClaim(_context, _to) {
        setContext(_context, _to);
        _incrementMintCounter();
        _mint(_to, id, amount, data);
    }

    /**
     * @dev Mints multiple ids to a wallet (called by owner)
     *
     * @param to address to mint to
     * @param ids token ids to be minted.
     */
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external onlyOwner whenNotPaused {
        _mintBatch(to, ids, amounts, data);
    }

    function mintAllowlisted(
        address _to,
        uint[] memory ids,
        uint[] memory amounts
    ) public nonReentrant whenNotPaused trustedAllowlist {
        _mintBatch(_to, ids, amounts, "");
    }

    modifier trustedAllowlist() {
        require(
            _msgSender() == getTrustedAllowlist(),
            "Call from invalid Allowlist"
        );
        _;
    }

    function getTrustedAllowlist() public view returns (address newAllowlist) {
        return _trustedAllowlistContract;
    }

    function setTrustedAllowlist(address newAllowlist) external onlyOwner {
        address oldAllowlist = _trustedAllowlistContract;
        _trustedAllowlistContract = newAllowlist;
        emit SetAllowlistContract(oldAllowlist, newAllowlist);
    }

    function lockMetaData() external onlyOwner {
        _isMetaLocked = true;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

