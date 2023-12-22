// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "./ERC1155.sol";
import "./Ownable.sol";
import "./IERC20.sol";

/// @title HonestWork Starter NFT
/// @author @takez0_o
/// @notice Starter Membership NFT's to be used in the platform
contract StarterNFT is ERC1155, Ownable {
    uint256 public fee = 10e18;
    uint256 public cap = 10000;
    string public baseUri;
    mapping(address => bool) public whitelistedTokens;
    bool public isPaused = false;

    event Mint(uint256 id, uint256 amount, address user);

    constructor(string memory _baseUri, address[] memory _whitelistedTokens)
        ERC1155(_baseUri)
    {
        baseUri = _baseUri;
        for (uint256 i = 0; i < _whitelistedTokens.length; i++) {
            whitelistedTokens[_whitelistedTokens[i]] = true;
        }
    }

    //-----------------//
    //  admin methods  //
    //-----------------//

    function setBaseUri(string memory _baseUri) external onlyOwner {
        baseUri = _baseUri;
    }

    function set_cap(uint256 _cap) external onlyOwner {
        cap = _cap;
    }

    function whitelistToken(address _token) external onlyOwner {
        whitelistedTokens[_token] = true;
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function pause() external onlyOwner {
        isPaused = true;
    }

    function unpause() external onlyOwner {
        isPaused = false;
    }

    function removeWhitelistToken(address _token) external onlyOwner {
        whitelistedTokens[_token] = false;
    }

    //--------------------//
    //  internal methods  //
    //--------------------//

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    //--------------------//
    //  mutative methods  //
    //--------------------//

    function publicMint(address _token) external whenNotPaused {
        require(whitelistedTokens[_token], "token not whitelisted");
        IERC20(_token).transferFrom(msg.sender, address(this), fee);
        _mint(msg.sender, 1, 1, "");
        emit Mint(1, 1, msg.sender);
    }

    //----------------//
    //  view methods  //
    //----------------//

    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(ERC1155)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    function getWhitelistToken(address _token) external view returns (bool) {
        return whitelistedTokens[_token];
    }

    function uri(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        return string(abi.encodePacked(baseUri, _toString(_tokenId)));
    }

    //----------------//
    //   modifiers    //
    //----------------//

    modifier whenNotPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }
}

