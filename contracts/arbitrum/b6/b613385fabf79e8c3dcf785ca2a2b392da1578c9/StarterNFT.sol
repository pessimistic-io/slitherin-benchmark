// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC721.sol";
import "./Ownable.sol";
import "./IERC20.sol";

/// @title HonestWork Starter NFT
/// @author @takez0_o
/// @notice Starter Membership NFT's to be used in the platform
contract StarterNFT is ERC721, Ownable {
    string public baseuri;
    uint256 public fee = 10e18;
    uint256 public cap = 10000;
    uint256 public id = 1;
    address[] public whitelist;
    bool public paused = false;
    bool public single_asset = true;

    event Mint(uint256 id, address user);

    constructor(string memory _baseuri, address _whitelist)
        ERC721("HonestWork Starter", "HWS")
    {
        baseuri = _baseuri;
        whitelist.push(_whitelist);
        _mint(msg.sender, 0);
    }

    //-----------------//
    //  admin methods  //
    //-----------------//

    function admint() external onlyOwner {
        require(id < cap, "cap reached");
        _mint(msg.sender, id);
        emit Mint(id, msg.sender);
        id++;
    }

    function setBaseUri(string memory _baseuri) external onlyOwner {
        baseuri = _baseuri;
    }

    function setCap(uint256 _cap) external onlyOwner {
        cap = _cap;
    }

    function setSingleAsset(bool _single_asset) external onlyOwner {
        single_asset = _single_asset;
    }

    function whitelistToken(address _token) external onlyOwner {
        whitelist.push(_token);
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function removeWhitelistToken(address _token) external onlyOwner {
        for (uint256 i = 0; i < whitelist.length; i++) {
            if (whitelist[i] == _token) {
                delete whitelist[i];
            }
        }
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function withdraw(address _token) external onlyOwner {
        IERC20(_token).transfer(
            msg.sender,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function withdraw() external onlyOwner {
        for (uint256 i = 0; i < whitelist.length; i++) {
            IERC20(whitelist[i]).transfer(
                msg.sender,
                IERC20(whitelist[i]).balanceOf(address(this))
            );
        }
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

    function mint(address _token) external whenNotPaused whitelisted(_token) {
        require(id < cap, "cap reached");
        IERC20(_token).transferFrom(msg.sender, address(this), fee);
        _mint(msg.sender, id);
        emit Mint(id, msg.sender);
        id++;
    }

    //----------------//
    //  view methods  //
    //----------------//

    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(ERC721)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    function tokenURI(uint256 _tokenid)
        public
        view
        override
        returns (string memory)
    {
        if (single_asset) {
            return string(abi.encodePacked(baseuri, "1"));
        } else {
            return string(abi.encodePacked(baseuri, _toString(_tokenid)));
        }
    }

    function getWhitelist() external view returns (address[] memory) {
        return whitelist;
    }

    //----------------//
    //   modifiers    //
    //----------------//

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    modifier whitelisted(address _token) {
        bool isWhitelisted = false;
        for (uint256 i = 0; i < whitelist.length; i++) {
            if (whitelist[i] == _token) {
                isWhitelisted = true;
            }
        }
        require(isWhitelisted, "not whitelisted");
        _;
    }
}

