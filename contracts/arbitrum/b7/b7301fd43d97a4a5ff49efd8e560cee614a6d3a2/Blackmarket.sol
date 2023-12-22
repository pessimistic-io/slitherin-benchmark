// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./Ownable.sol";
contract Blackmarket is ERC1155, Ownable {
    string private _name;
    string private _symbol;

    //tracking token uris for ipfs hashes support
    mapping (uint256 => string) private _tokenURIs;
    address public admin;
    address public gameManager;

    constructor(address _admin, address _gameManager) ERC1155("https://dopewarz.io/api/item/{id}.json") {
        admin = _admin;
        gameManager = _gameManager;

        _name = "Dopewarz";
        _symbol = "DOPEWARZ";
    }

    modifier onlyMangers {
        require(msg.sender == address(gameManager), "Address not authorized to call this function");
        _;
    }
    modifier onlyAdmins {
        require(msg.sender == address(admin) || msg.sender == address(gameManager), "Address not authorized to call this function");
        _;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }


    /// mints a single new token 
    /// @param receiver the wallet address against which the token needs to be minted
    /// @param id the unique identifier for the token
    /// @param tokenURI the token URI assigned to be assigned to that token ID
    /// @dev mints a single new token for the supplied address
    function mint(address receiver, uint256 id, string memory tokenURI) external onlyAdmins {
        _mint(receiver, id, 1, "");
        _setTokenUri(id, tokenURI); 
    }

    /// mints a batch of new tokens
    /// @param receiver the wallet address against which the tokens need to be minted
    /// @param ids the unique identifiers for the tokens
    /// @param tokenURIs the token URIs assigned to be assigned to that token ID
    /// @dev mints a batch of new tokens for the supplied address
    function mintBatch(address receiver, uint256[] memory ids, uint256[] memory amounts, string[] memory tokenURIs) external onlyAdmins {
        require(ids.length == amounts.length, "Mismatch in number of ids and amounts");
        require(ids.length == tokenURIs.length, "Mismatch in number of ids and tokenURIs");

        _mintBatch(receiver, ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            _setTokenUri(ids[i], tokenURIs[i]);
        }
    }

    /// burns a users token
    /// @param account the wallet address to burn token from
    /// @param id the unique identifier for the token
    /// @param amount the amount to be burned
    /// @dev burns a given users token based on the amount and toke id supplied, can be called by the owner only.
    function burn(
        address account,
        uint256 id,
        uint256 amount
    ) external onlyMangers{
        _burn(account, id, amount);
        _resetTokenUri(id);
    }

    /// Get token URI against a given tokenId
    /// @param tokenId the unique identifier for the token
    /// @return tokenURI the token URI assigned to that token ID
    function uri(uint256 tokenId) override public view 
    returns (string memory) { 
        return(_tokenURIs[tokenId]); 
    } 

    /// Store `_tokenURIs`.
    /// @param tokenId the token id against which to update tokenURI
    /// @param tokenURI the token URI to be assigned to the token id
    /// @dev stores the token URI for each token ID
    function _setTokenUri(uint256 tokenId, string memory tokenURI)
    private {
         _tokenURIs[tokenId] = tokenURI; 
    }

    /// Reset `_tokenURIs`.
    /// @param tokenId the token id against which to update tokenURI
    /// @dev removes the token URI for the provided token ID
    function _resetTokenUri(uint256 tokenId)
    private {
         delete _tokenURIs[tokenId]; 
    } 


    function setAdmin (address account) external onlyOwner{
        admin = account;
    }

    function setGameManager (address account) external onlyOwner{
        gameManager = account;
    }

}
