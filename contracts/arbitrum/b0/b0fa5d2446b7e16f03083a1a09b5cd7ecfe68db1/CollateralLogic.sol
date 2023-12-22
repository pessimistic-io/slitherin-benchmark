// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PriceConvertor.sol";
import "./IPool.sol";
import "./IERC20X.sol";
import "./ISyntheX.sol";
import "./Errors.sol";
import "./SafeERC20Upgradeable.sol";
import "./IWETH.sol";

library CollateralLogic {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event CollateralParamsUpdated(address indexed asset, uint cap, uint baseLTV, uint liqThreshold, uint liqBonus, bool isEnabled);
    
    event CollateralEntered(address indexed user, address indexed collateral);
    event CollateralExited(address indexed user, address indexed collateral);
    
    event Deposit(address indexed user, address indexed asset, uint256 amount);
    event Withdraw(address indexed user, address indexed asset, uint256 amount);

    /**
     * @notice Enable a collateral
     * @param _collateral The address of the collateral
     */
    function enterCollateral(
        address _collateral,
        mapping(address => DataTypes.Collateral) storage collaterals,
        mapping(address => mapping(address => bool)) storage accountMembership,
        mapping(address => address[]) storage accountCollaterals
    ) public {
        // get collateral pool
        DataTypes.Collateral storage collateral = collaterals[_collateral];

        require(collateral.isActive, Errors.ASSET_NOT_ACTIVE);

        // ensure that the user is not already in the pool
        require(!accountMembership[_collateral][msg.sender], Errors.ACCOUNT_ALREADY_ENTERED);
        // enable account's collateral membership
        accountMembership[_collateral][msg.sender] = true;
        // add to account's collateral list
        accountCollaterals[msg.sender].push(_collateral);

        emit CollateralEntered(msg.sender, _collateral);
    }

    /**
     * @notice Exit a collateral
     * @param _collateral The address of the collateral
     */
    function exitCollateral(
        address _collateral,
        mapping(address => mapping(address => bool)) storage accountMembership,
        mapping(address => address[]) storage accountCollaterals
    ) public {
        accountMembership[_collateral][msg.sender] = false;
        // remove from list
        for (uint i = 0; i < accountCollaterals[msg.sender].length; i++) {
            if (accountCollaterals[msg.sender][i] == _collateral) {
                accountCollaterals[msg.sender][i] = accountCollaterals[msg.sender][accountCollaterals[msg.sender].length - 1];
                accountCollaterals[msg.sender].pop();

                emit CollateralExited(msg.sender, _collateral); 
                break;
            }
        }
    }

    function depositETH(
        address _account,
        address WETH_ADDRESS,
        uint _amount,
        mapping(address => DataTypes.Collateral) storage collaterals,
        mapping(address => mapping(address => bool)) storage accountMembership,
        mapping(address => mapping(address => uint)) storage accountCollateralBalance,
        mapping(address => address[]) storage accountCollaterals
    ) public {
        // wrap ETH
        IWETH(WETH_ADDRESS).deposit{value: _amount}();
        // deposit collateral
        depositInternal(
            _account,
            WETH_ADDRESS,
            _amount,
            collaterals,
            accountMembership,
            accountCollateralBalance,
            accountCollaterals
        );
    }

    function depositWithPermit(
        address _account,
        address _collateral,
        uint _amount,
        uint _approval, 
        uint _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s,
        mapping(address => DataTypes.Collateral) storage collaterals,
        mapping(address => mapping(address => bool)) storage accountMembership,
        mapping(address => mapping(address => uint)) storage accountCollateralBalance,
        mapping(address => address[]) storage accountCollaterals
    ) public {
        // permit approval
        IERC20PermitUpgradeable(_collateral).permit(msg.sender, address(this), _approval, _deadline, _v, _r, _s);
        // deposit collateral
        depositERC20(_account, _collateral, _amount, collaterals, accountMembership, accountCollateralBalance, accountCollaterals);
    }

    function depositERC20(
        address _account,
        address _collateral,
        uint _amount,
        mapping(address => DataTypes.Collateral) storage collaterals,
        mapping(address => mapping(address => bool)) storage accountMembership,
        mapping(address => mapping(address => uint)) storage accountCollateralBalance,
        mapping(address => address[]) storage accountCollaterals
    ) public {
        // transfer in collateral
        IERC20Upgradeable(_collateral).transferFrom(msg.sender, address(this), _amount);
        // deposit collateral
        depositInternal(
            _account,
            _collateral,
            _amount,
            collaterals,
            accountMembership,
            accountCollateralBalance,
            accountCollaterals
        );
    }

    /**
     * @notice Deposit collateral
     * @param _collateral The address of the erc20 collateral
     * @param _amount The amount of collateral to deposit
     */
    function depositInternal(
        address _account,
        address _collateral,
        uint _amount,
        mapping(address => DataTypes.Collateral) storage collaterals,
        mapping(address => mapping(address => bool)) storage accountMembership,
        mapping(address => mapping(address => uint)) storage accountCollateralBalance,
        mapping(address => address[]) storage accountCollaterals
    ) public {
        // get collateral market
        DataTypes.Collateral storage collateral = collaterals[_collateral];
        // ensure collateral is globally enabled
        require(collateral.isActive, Errors.ASSET_NOT_ACTIVE);

        // ensure user has entered the market
        if(!accountMembership[_collateral][_account]){
            enterCollateral(
                _collateral,
                collaterals,
                accountMembership,
                accountCollaterals
            );
        }
        
        // Update balance
        accountCollateralBalance[_account][_collateral] += _amount;

        // Update collateral supply
        collateral.totalDeposits += _amount;
        require(collateral.totalDeposits <= collateral.cap, Errors.EXCEEDED_MAX_CAPACITY);

        // emit event
        emit Deposit(_account, _collateral, _amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Withdraw                                  */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @notice Deposit collateral
     * @param _collateral The address of the erc20 collateral
     * @param _amount The amount of collateral to deposit
     */
    function withdraw(
        address _collateral,
        uint _amount,
        mapping(address => DataTypes.Collateral) storage collaterals,
        mapping(address => mapping(address => uint)) storage accountCollateralBalance
    ) public {
        require(_amount > 0, Errors.ZERO_AMOUNT);
        // Process withdraw
        DataTypes.Collateral storage supply = collaterals[_collateral];
        // check deposit balance
        uint depositBalance = accountCollateralBalance[msg.sender][_collateral];
        // allow only upto their deposit balance
        require(depositBalance >= _amount, Errors.INSUFFICIENT_BALANCE);
        // Update balance
        accountCollateralBalance[msg.sender][_collateral] = depositBalance - _amount;
        // Update collateral supply
        supply.totalDeposits -= _amount;
        // Emit successful event
        emit Withdraw(msg.sender, _collateral, _amount);
    }
}
