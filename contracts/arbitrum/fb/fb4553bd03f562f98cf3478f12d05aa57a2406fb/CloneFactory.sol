//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/proxy/Clones.sol";

contract CloneFactory {
    mapping(uint256 => address) public adderMap;

    function createNewLogic(address implementation, uint256 adder) external {
        address lc = Clones.clone(implementation);
        LogicContract(lc).initialize(adder);

        adderMap[adder] = lc;
    }
}

contract LogicContract {
    uint256 public adder;

    function initialize(uint256 _adder) external {
        adder = _adder;
    }

    function addSomething(uint256 _a) public view returns (uint256 result) {
        return _a + adder;
    }
}

library Clones {
    function clone(address implementation) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(
                ptr,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(
                add(ptr, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }
}

