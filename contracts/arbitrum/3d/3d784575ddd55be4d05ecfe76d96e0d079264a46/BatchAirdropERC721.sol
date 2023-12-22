// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721EnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./AddressUpgradeable.sol";

import "./console.sol";

interface ICloneFactory {
    function getProtocolFeeAndRecipient(address _contract) external view returns (uint256, address);
}

contract BatchAirdropERC721 is Initializable, ERC721EnumerableUpgradeable, OwnableUpgradeable {
    using StringsUpgradeable for string;
    using AddressUpgradeable for address;
    
    bool public isFrozen = false;
    string public baseURI;
    string public baseExtension;
    address public _delegate;
    ICloneFactory public immutable cloneFactory;
    

    modifier onlyDelegate() {
        require(msg.sender == _delegate, "Only the delegate can call this function");
        _;
    }
    constructor(address _cloneFactory) {
        cloneFactory = ICloneFactory(_cloneFactory);
    }

    function initialize(
        address payable _owner, 
        string[] memory _stringData, 
        uint [] memory _uintData,
        bool[] memory _boolData,
        address[] memory _addressData)
        external  initializer  {
        require(_stringData.length == 4, "Missing string data (name, symbol, baseURI, baseExtension)");
        require(_uintData.length == 0, "Should not receiev any uint data");
        require(_boolData.length == 0, "Should not recieve any bool data");
        require(_addressData.length == 1, "Missing address data (delegateAddress)");

        __ERC721Enumerable_init();
        __ERC721_init(_stringData[0], _stringData[1]);
        __Ownable_init_unchained();

        transferOwnership(_owner);


        baseURI = _stringData[2];
        baseExtension = _stringData[3];
        _delegate = _addressData[0];
    }

    /**
     * Warning calling this function will disable administrative access to changing
     * contract paramaters.
     */
    function freezeContract() public onlyOwner {
        require(!isFrozen, "Contract is already frozen.");
        isFrozen = true;
    }

    function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
        require(!isFrozen, "Contract is frozen.");

        baseExtension = _newBaseExtension;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }


    function setBaseURI(string memory __baseURI) public onlyOwner {
        require(!isFrozen, "Contract is frozen.");
        baseURI = __baseURI;
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token.");
        return (
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, StringsUpgradeable.toString(_tokenId), baseExtension))
                : ""
        );
    }
    /*
    *
    * Call this after airdrop is complete!
    *
     */

    function revokeDelegate() public {
        require(msg.sender == owner() || msg.sender == _delegate, "Only the owner or the delegate can call this function");
        require(_delegate != address(0x0), "Delegate has already been revoked");
        _delegate = address(0x0);
    }


    function batchAirdrop(address [] calldata addresses) public onlyDelegate { 
        require(!isFrozen, "Contract is frozen.");
        for (uint256 i = 0; i < addresses.length; i++) {
            _safeMint(addresses[i], totalSupply());
        }
    }
    function batchMint(address[] calldata addresses) public onlyOwner {
        require(!isFrozen, "Contract is frozen.");
        for (uint256 i = 0; i < addresses.length; i++) {
            _safeMint(addresses[i], totalSupply());
        }
    }
}
