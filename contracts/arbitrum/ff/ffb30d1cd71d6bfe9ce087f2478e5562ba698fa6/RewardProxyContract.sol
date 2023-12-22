// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./Ownable.sol";

contract RewardProxyContract is Ownable {

    address public rewardContractAddress;

    constructor(address dispatcher, address rewardContract) {
        initContractInner(dispatcher, rewardContract);
    }

    function upgradeLogicContract(address dispatcher, address rewardContract) external onlyOwner {
        initContractInner(dispatcher, rewardContract);
    }

    function initContractInner(address dispatcher, address _rewardContract) internal {
        rewardContractAddress = _rewardContract;
        bytes memory data = abi.encodeWithSignature("initialize(address)", dispatcher);
        (bool success,) = rewardContractAddress.delegatecall(data);
        require(success, "Initialization failed");
    }

    receive() external payable {}

    fallback() external payable {
        address implementation = rewardContractAddress;
        require(implementation != address(0));

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), implementation, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }
}

