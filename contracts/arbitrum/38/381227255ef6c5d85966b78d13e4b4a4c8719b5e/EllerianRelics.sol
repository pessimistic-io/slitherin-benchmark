// contracts/GameRelics.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./Strings.sol";
import "./Ownable.sol";

/** 
 * Tales of Elleria
*/
contract EllerianRelics is ERC1155, Ownable {
    using Strings for uint256;

    // Keeps track of admin addresses.
    mapping (address => bool) private _approvedAddresses;
    mapping (uint256 => address) private _relicManagerAddress;

    string private uriPrefix = "https://cdn.talesofelleria.com/assets/items/metadata/";
    string private uriSuffix = ".json";

    address private relicBridgeAddress;

    constructor() ERC1155("overrided") {
        _approvedAddresses[msg.sender] = true;
    }

    /**
    * Links to our other contracts to get things working.
    */
    function SetAddresses(address _bridgeAddr) external onlyOwner {
        relicBridgeAddress = _bridgeAddr;
    }    
    
    /**
    * Allows approval of certain contracts for balance control. (bridge)
    */
    function SetApprovedAddress(address _address, bool _allowed) public onlyOwner {
        _approvedAddresses[_address] = _allowed;
    }   
    
    /**
    * Delegates minting of specific relics to contracts (cross-metaverse integrations)
    */
    function SetRelicManager(uint256 _id, address _address) external onlyOwner {
        _relicManagerAddress[_id] = _address;
    }

    /**
    * Configures where metadata is stored.
    */
    function setUri(string memory _prefix, string memory _suffix) external onlyOwner {
        uriPrefix = _prefix;
        uriSuffix = _suffix;
    }

    /**
    * Retrieves the metadata for a specific id.
    */
    function uri(uint256 tokenId) override public view returns (string memory) {
        return (string(abi.encodePacked(
            uriPrefix, Strings.toString(tokenId), uriSuffix
        )));
    }

    function mint(address to, uint256 id, uint256 amount) 
    external {
        require(_approvedAddresses[msg.sender], "Not Approved");
        
        _mint(to, id, amount, '');
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts)
    external {
        require(_approvedAddresses[msg.sender], "Not Approved");

        _mintBatch(to, ids, amounts, '');
    }

    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts)
    external {
        require(_approvedAddresses[msg.sender], "Not Approved");

        _burnBatch(from, ids, amounts);
    }

    /* 
    * Allows a custom contract to mint relics.
    * Allows for customized logic.
    */
    function externalMint(address to, uint256 id, uint256 amount) external {
        require(msg.sender == _relicManagerAddress[id], "External Mint Denied");
        
        _mint(to, id, amount, '');

        emit ExternalMint(to, id, amount);
    }

    event ExternalMint(address to, uint256 id, uint256 amount);
}
