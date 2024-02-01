pragma solidity ^0.8.0;

import "./FarmingBase.sol";
import "./StargateAddressUtils.sol";

contract StargateClaimAuthorizer is FarmingBaseACL {
    bytes32 public constant NAME = "StargateClaimAuthorizer";
    uint256 public constant VERSION = 1;

    address public immutable stakingPool;

    constructor(address _owner, address _caller) FarmingBaseACL(_owner, _caller) {
        (stakingPool, , ) = getAddresses();
    }

    /// @dev for lp staking
    function deposit(uint256 _pid, uint256 amount) public view onlyContract(stakingPool) {
        require(amount == 0, "can only claim");
        _checkAllowPoolId(_pid);
    }

    function contracts() public view override returns (address[] memory _contracts) {
        _contracts = new address[](1);
        _contracts[0] = stakingPool;
    }
}

