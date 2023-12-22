// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";

import { ICreditToken } from "./ICreditToken.sol";
import { ICreditTokenStaker } from "./ICreditTokenStaker.sol";
import { IBaseReward } from "./IBaseReward.sol";
import { IVaultRewardDistributor } from "./IVaultRewardDistributor.sol";

contract CreditTokenStaker is Initializable, ICreditTokenStaker {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public override creditToken;

    mapping(address => bool) private owners;

    modifier onlyOwners() {
        require(isOwner(msg.sender), "CreditTokenStaker: Caller is not an owner");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _owner) external initializer {
        require(_owner != address(0), "CreditTokenStaker: _owner cannot be 0x0");

        owners[_owner] = true;
    }

    function addOwner(address _newOwner) public onlyOwners {
        require(_newOwner != address(0), "CreditTokenStaker: _newOwner cannot be 0x0");
        require(!isOwner(_newOwner), "CreditTokenStaker: _newOwner is already owner");

        owners[_newOwner] = true;

        emit NewOwner(msg.sender, _newOwner);
    }

    function addOwners(address[] calldata _newOwners) external onlyOwners {
        for (uint256 i = 0; i < _newOwners.length; i++) {
            addOwner(_newOwners[i]);
        }
    }

    function removeOwner(address _owner) external onlyOwners {
        require(_owner != address(0), "CreditTokenStaker: _owner cannot be 0x0");
        require(isOwner(_owner), "CreditTokenStaker: _owner is not an owner");

        owners[_owner] = false;

        emit RemoveOwner(msg.sender, _owner);
    }

    function isOwner(address _owner) public view returns (bool) {
        return owners[_owner];
    }

    function stake(address _vaultRewardDistributor, uint256 _amountIn) external override onlyOwners returns (bool) {
        require(_vaultRewardDistributor != address(0), "CreditTokenStaker: _vaultRewardDistributor cannot be 0x0");

        ICreditToken(creditToken).mint(address(this), _amountIn);
        _approve(creditToken, _vaultRewardDistributor, _amountIn);
        IVaultRewardDistributor(_vaultRewardDistributor).stake(_amountIn);

        emit Stake(msg.sender, _vaultRewardDistributor, _amountIn);

        return true;
    }

    function withdraw(address _vaultRewardDistributor, uint256 _amountOut) external override onlyOwners returns (bool) {
        require(_vaultRewardDistributor != address(0), "CreditTokenStaker: _vaultRewardDistributor cannot be 0x0");

        IVaultRewardDistributor(_vaultRewardDistributor).withdraw(_amountOut);
        ICreditToken(creditToken).burn(address(this), _amountOut);

        emit Withdraw(msg.sender, _vaultRewardDistributor, _amountOut);

        return true;
    }

    function stakeFor(
        address _collateralReward,
        address _recipient,
        uint256 _amountIn
    ) external override onlyOwners returns (bool) {
        require(_collateralReward != address(0), "CreditTokenStaker: _collateralReward cannot be 0x0");
        require(_recipient != address(0), "CreditTokenStaker: _recipient cannot be 0x0");

        ICreditToken(creditToken).mint(address(this), _amountIn);
        _approve(creditToken, _collateralReward, _amountIn);
        IBaseReward(_collateralReward).stakeFor(_recipient, _amountIn);

        emit StakeFor(msg.sender, _collateralReward, _recipient, _amountIn);

        return true;
    }

    function withdrawFor(
        address _collateralReward,
        address _recipient,
        uint256 _amountOut
    ) external override onlyOwners returns (bool) {
        require(_collateralReward != address(0), "CreditTokenStaker: _collateralReward cannot be 0x0");
        require(_recipient != address(0), "CreditTokenStaker: _recipient cannot be 0x0");

        IBaseReward(_collateralReward).withdrawFor(_recipient, _amountOut);
        ICreditToken(creditToken).burn(address(this), _amountOut);

        emit WithdrawFor(msg.sender, _collateralReward, _recipient, _amountOut);

        return true;
    }

    function setCreditToken(address _creditToken) external onlyOwners {
        require(_creditToken != address(0), "CreditTokenStaker: _creditToken cannot be 0x0");
        require(creditToken == address(0), "CreditTokenStaker: Cannot run this function twice");

        creditToken = _creditToken;

        emit SetCreditToken(_creditToken);
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }
}

