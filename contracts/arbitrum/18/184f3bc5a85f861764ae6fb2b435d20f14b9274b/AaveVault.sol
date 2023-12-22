// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseBuildingBlock.sol";
import "./IAaveVault.sol";

/**
 * @author DeCommas team
 * @title Aave protocol interface to open, close positions and borrow assets
 */
contract AaveVault is BaseBuildingBlock, IAaveVault {
    IPoolAddressesProvider public aaveProvider;
    IPool public aaveLendingPool;
    IWETHGateway public wethGateway;
    IRewardsController public rewardsController;
    address public wavaxVariableDebtToken;
    address public aaveStrategy;

    /**
     * @notice Initializer
     * @param _data encode for:
     * @dev aaveProvider aave Pool provider address
     * @dev _wethGateway weth network gateway
     * @dev _rewardsController rewards controller address
     */
    function initialize(bytes memory _data) public initializer {
        AaveVaultInitParams memory initParams = abi.decode(
            _data,
            (AaveVaultInitParams)
        );

        require(
            address(initParams.aaveProviderAddress) != address(0),
            "AaveVault::initialize: aaveProvider address zero"
        );
        require(
            address(initParams.wethGatewayAddress) != address(0),
            "AaveVault::initialize: wethGateway address zero"
        );
        require(
            address(initParams.rewardsControllerAddress) != address(0),
            "AaveVault::initialize: rewardsController address zero"
        );
        require(
            address(initParams.actionPoolDcRouter) != address(0),
            "AaveVault::initialize: action pool address zero"
        );
        require(
            address(initParams.nativeLZEndpoint) != address(0),
            "AaveVault::initialize: lzEndpoint address zero"
        );
        require(
            address(initParams.usdcToken) != address(0),
            "AaveVault::initialize: usdc address zero"
        );
        require(
            address(initParams.wavaxVariableDebtTokenAddress) != address(0),
            "AaveVault::initialize: wavaxVDebtToken address zero"
        );
        require(
            initParams.nativeId > 0,
            "AaveVault::initialize: id must be greater than 0"
        );
        require(
            initParams.actionPoolId > 0,
            "AaveVault::initialize: action pool id must be greater than 0"
        );

        __Ownable_init();
        __LzAppUpgradeable_init(address(initParams.nativeLZEndpoint));
        _transferOwnership(_msgSender());

        _nativeChainId = initParams.nativeId;
        _currentUSDCToken = address(initParams.usdcToken);
        lzEndpoint = initParams.nativeLZEndpoint;
        trustedRemoteLookup[initParams.actionPoolId] = abi.encodePacked(
            address(initParams.actionPoolDcRouter),
            address(this)
        );
        _actionPool = address(initParams.actionPoolDcRouter);

        aaveProvider = initParams.aaveProviderAddress;
        aaveLendingPool = IPool(aaveProvider.getPool());
        wethGateway = initParams.wethGatewayAddress;
        rewardsController = initParams.rewardsControllerAddress;
        wavaxVariableDebtToken = initParams.wavaxVariableDebtTokenAddress;
    }

    /**
     * @notice only access from strategy contract to pull funds
     * @param _asset  asset to transfer
     * @param _amount  amount to transfer
     */
    function transferToStrategy(address _asset, uint256 _amount)
        public
        override
        auth
    {
        if (_asset == address(0x0)) {
            (bool sent, ) = address(aaveStrategy).call{value: _amount}("");
            require(
                sent,
                "AaveVault::transferToStrategy: native transfer failed"
            );
        } else {
            require(
                IERC20(_asset).transfer(aaveStrategy, _amount),
                "AaveVault::transferToStrategy: ERC20 transfer failed"
            );
        }
    }

    /**
     * @notice set Strategy contract address
     */
    function setAaveStrategy(bytes memory _data) public override auth {
        aaveStrategy = _bytesToAddress(_data);
    }

    /**
     * @notice Allows a user to use the protocol in eMode
     * @param _data categoryId The id of the category
     * @dev id (0 - 255) defined by Risk or Pool Admins. categoryId == 0 ⇒ non E-mode category.
     */
    function setUserEMode(bytes memory _data) public override auth {
        uint8 categoryId = abi.decode(_data, (uint8));
        aaveLendingPool.setUserEMode(categoryId);
        emit SetUserEMode(categoryId);
    }

    /**
     * @notice Sets a an asset already deposited as collateral for a future borrow
     * @dev Supply collateral first, then setCollateralAsset
     * @param _data collateral Asset address
     */
    function setCollateralAsset(bytes memory _data) public override auth {
        address collateralAsset = _bytesToAddress(_data);
        if (collateralAsset == address(0)) {
            collateralAsset = wethGateway.getWETHAddress();
        }
        aaveLendingPool.setUserUseReserveAsCollateral(
            address(collateralAsset),
            true
        );
        emit SetCollateralEvent(IERC20(collateralAsset));
    }

    /**
     * @notice Opens a new position (supply collateral) as liquidity provider on AAVE
     * @param _data baseAsset asset address, amount to deposit
     */
    function openPosition(bytes memory _data) public override auth {
        (IERC20 baseAsset, uint256 amount, uint16 referralCode) = abi.decode(
            _data,
            (IERC20, uint256, uint16)
        );
        if (address(baseAsset) == address(0x0)) {
            require(
                amount <= address(this).balance,
                "AaveVault::openPosition: amount greater than native balance"
            );
            wethGateway.depositETH{value: amount}(
                address(aaveLendingPool),
                address(this),
                referralCode
            );
        } else {
            require(
                amount <= baseAsset.balanceOf(address(this)),
                "AaveVault::openPosition: amount greater than baseAsset balance"
            );
            baseAsset.approve(address(aaveLendingPool), amount);

            aaveLendingPool.supply(
                address(baseAsset),
                amount,
                address(this),
                referralCode
            );
        }

        emit OpenPositionEvent(baseAsset, amount);
    }

    /**
     * @notice Aave Borrows an asset
     * @param _data baseAsset address, amount to borrow
     */
    function borrow(bytes memory _data) public override auth {
        (
            IERC20 borrowAsset,
            uint256 amount,
            uint16 borrowRate,
            uint16 referralCode
        ) = abi.decode(_data, (IERC20, uint256, uint16, uint16));

        if (address(borrowAsset) == address(0x0)) {
            IDebtTokenBase(wavaxVariableDebtToken).approveDelegation(
                address(wethGateway),
                amount
            );
            wethGateway.borrowETH(
                address(aaveLendingPool),
                amount,
                borrowRate,
                referralCode
            );
        } else {
            aaveLendingPool.borrow(
                address(borrowAsset),
                amount,
                borrowRate,
                referralCode,
                address(this)
            );
        }
        emit BorrowEvent(borrowAsset, amount);
    }

    /**
     * @notice Repays a loan (partially or fully)
     * @dev using default Fixed rates
     */
    function repay(bytes memory _data) public override auth {
        (IERC20 asset, uint256 amount, uint16 borrowRate) = abi.decode(
            _data,
            (IERC20, uint256, uint16)
        );

        if (address(asset) == address(0x0)) {
            wethGateway.repayETH{value: amount}(
                address(aaveLendingPool),
                amount,
                borrowRate,
                address(this)
            );
        } else {
            asset.approve(address(aaveLendingPool), amount);
            aaveLendingPool.repay(
                address(asset),
                amount,
                borrowRate,
                address(this)
            );
        }
        emit RepayEvent(asset, amount);
    }

    /**
     * @notice Closes a position as liquidity provider on AAVE
     * @param _data asset address,amount to withdraw
     * @dev if asset[0] List of incentivized assets to check eligible distributions, The address of the user
     */
    function closePosition(bytes memory _data) public override auth {
        (IERC20 asset, uint256 amount) = abi.decode(_data, (IERC20, uint256));
        if (address(asset) == address(0x0)) {
            wethGateway.withdrawETH(
                address(aaveLendingPool),
                amount,
                address(this)
            );
        } else {
            aaveLendingPool.withdraw(address(asset), amount, address(this));
        }
        emit ClosePositionEvent(asset, amount);
    }

    /**
     * @notice Returns a list all rewards of a user, including already accrued and unrealized claimable rewards
     * @param _data List of incentivized assets to check eligible distributions, The address of the user
     **/
    function claimAllRewards(bytes memory _data) public override auth {
        (address[] memory assets, address user) = abi.decode(
            _data,
            (address[], address)
        );
        rewardsController.claimAllRewards(assets, user);
        emit ClaimedRewardsEvent(assets, user);
    }

    function _bytesToAddress(bytes memory _bys)
        private
        pure
        returns (address addr)
    {
        assembly {
            addr := mload(add(_bys, 20))
        }
    }

    modifier auth() {
        require(
            msg.sender == address(this) ||
                msg.sender == _actionPool ||
                msg.sender == aaveStrategy,
            "AaveVault::auth:Only self call"
        );
        _;
    }

    uint256[50] private __gap;
}

