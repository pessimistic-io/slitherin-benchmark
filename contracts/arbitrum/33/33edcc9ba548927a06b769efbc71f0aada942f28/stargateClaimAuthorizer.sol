pragma solidity ^0.8.0;

import "./FarmingBase.sol";

contract StargateClaimAuthorizer is FarmingBaseACL {
    bytes32 public NAME = "StargateClaimAuthorizer";
    uint256 public VERSION = 1;

    address public immutable stakingPool;

    constructor(address _stakingPool, address _owner, address _caller) FarmingBaseACL(_owner, _caller) {
        stakingPool = _stakingPool;
    }

    /// @dev for lp staking
    function deposit(uint256 _pid, uint256 amount) public view onlyContract(stakingPool) {
        require(amount == 0, "can only claim");
        checkAllowPoolId(_pid);
    }

    function contracts() public view override returns (address[] memory _contracts) {
        _contracts = new address[](1);
        _contracts[0] = stakingPool;
    }
}

