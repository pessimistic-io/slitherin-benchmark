pragma solidity ^0.8.0;

import "./FarmingBase.sol";
import "./IStargateFactory.sol";

contract StargateWithdrawAuthorizer is FarmingBaseACL {
    bytes32 public NAME = "StargateWithdrawAuthorizer";
    uint256 public VERSION = 1;

    address public immutable router;
    address public immutable stakingPool;
    IStargateFactory public immutable stargateFactory;

    constructor(
        address _router,
        address _stakingPool,
        IStargateFactory _factory,
        address _owner,
        address _caller
    ) FarmingBaseACL(_owner, _caller) {
        router = _router;
        stakingPool = _stakingPool;
        stargateFactory = _factory;
    }

    /// @dev for stargate router
    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256, //_amountLD
        address _to
    ) external view onlyContract(router) {
        address poolAddress = stargateFactory.getPool(_srcPoolId);
        _checkAllowPoolAddress(poolAddress);
        _checkRecipient(_to);
    }

    /// @dev for lp staking
    function withdraw(
        uint256 _pid,
        uint256 //amount
    ) public view onlyContract(stakingPool) {
        _checkAllowPoolId(_pid);
    }

    function contracts() public view override returns (address[] memory _contracts) {
        _contracts = new address[](2);
        _contracts[0] = router;
        _contracts[1] = stakingPool;
    }
}

