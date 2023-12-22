// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1155Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Math.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./SafeMath.sol";

contract FaceNFTCollection is Initializable, ERC1155Upgradeable, OwnableUpgradeable, ERC1155BurnableUpgradeable, ERC1155SupplyUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) initializer public {
        __ERC1155_init("ipfs://bafybeiel4sberm4omgi7lcbmghjp2n2qqzukqsu2dghx6upbsfdb37gfnq/{id}.json");
        __Ownable_init(initialOwner);
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __UUPSUpgradeable_init();

        _mint(msg.sender, 1, 20, "");
        _mint(msg.sender, 2, 2, "");
        _mint(msg.sender, 3, 1, "");
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        public
        onlyOwner
    {
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyOwner
    {
        _mintBatch(to, ids, amounts, data);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._update(from, to, ids, values);
    }



    function stuffstuffstuff() pure public virtual returns (string memory) {
        return "v2!";
    }    

}

contract FaceNFTCollectionV2 is FaceNFTCollection {
    uint fee;
    function version() pure public virtual returns (string memory) {
        return "v2!";
    }
}

contract FaceNFTCollectionV3 is FaceNFTCollectionV2 {
    uint tax;

    function version() pure public virtual override returns (string memory) {
        return "v3!";
    }
}

contract FaceNFTCollectionV4 is FaceNFTCollectionV3 {
    using Math for uint256;

    function safeTransferFrom(address sender, address recipient, uint256 id, uint256 value, bytes memory data) public virtual override  {
        // why cant we override internal function _safeTransferFrom 
        if (value > 1) {
            super.safeTransferFrom(sender, recipient, id, value - 1, data);
            super.safeTransferFrom(sender, owner(), id, 1, data);
        }
    }    
}

contract FaceNFTCollectionV5 is FaceNFTCollectionV4 {
    using SafeMath for uint256;
    ThingInterface public thingContract;

    function version() pure public override returns (string memory) {
        return "v5!";
    }
    function setThingContractAddress(address _addy) public {
        thingContract = ThingInterface(_addy);
    }    

   function safeTransferFrom(address sender, address recipient, uint256 id, uint256 amount, bytes memory data) public virtual override  {
         // is it more efficient to check fo shadow ownership before calling attack
        // super._transfer(sender, recipient, amount);
        super.safeTransferFrom(sender, recipient, id, amount, data);

        if (address(thingContract) != address(0)) {
            thingContract.doThing(sender, recipient, amount);
        }
    }    
}

interface ThingInterface {
    function doThing(address sender, address recipient, uint256 amount) external;
}

