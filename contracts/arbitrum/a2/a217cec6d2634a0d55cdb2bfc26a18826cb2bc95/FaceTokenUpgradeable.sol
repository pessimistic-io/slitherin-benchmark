// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Math.sol";
import "./SafeMath.sol";


contract FaceToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __ERC20_init("FaceToken", "Face8");
        __Ownable_init();
        __UUPSUpgradeable_init();

        _mint(msg.sender, 100000 * 10 ** decimals());
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
}

contract FaceTokenV2 is FaceToken {
    uint fee;
    function version() pure public virtual returns (string memory) {
        return "v2!";
    }
}


contract FaceTokenV3 is FaceTokenV2 {
    uint tax;

    function version() pure public virtual override returns (string memory) {
        return "v3!";
    }
}

contract FaceTokenV4 is FaceTokenV3 {
    using SafeMath for uint256;

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        // is it more efficient to check fo shadow ownership before calling attack
        super._transfer(sender, recipient, amount - 100);
        super._transfer(sender, owner(), 100);

    }    
}

contract FaceTokenV5 is FaceTokenV4 {
    using SafeMath for uint256;
    ThingInterface public thingContract;

    function version() pure public override returns (string memory) {
        return "v5!";
    }
    function setThingContractAddress(address _addy) public {
        thingContract = ThingInterface(_addy);
    }    

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        // is it more efficient to check fo shadow ownership before calling attack
        super._transfer(sender, recipient, amount);
        if (address(thingContract) != address(0)) {
            thingContract.doThing(sender, recipient, amount);
        }
    }    
}

interface ThingInterface {
    function doThing(address sender, address recipient, uint256 amount) external;
}

