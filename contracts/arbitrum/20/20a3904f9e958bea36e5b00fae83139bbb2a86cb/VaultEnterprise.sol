// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma abicoder v2;

import "./IUniswapV3Pool.sol";
import "./FullMath.sol";
import "./ERC20Permit.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./IVaultSwap.sol";
import "./IVaultEnterprise.sol";
import "./VaultEnterpriseHelper.sol";

contract VaultEnterprise is
    IVaultEnterprise,
    ERC20Permit,
    ReentrancyGuard,
    AccessControl
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    bytes32 public constant COMPOUND_ROLE = keccak256("COMPOUND_ROLE");
    bytes32 public constant TICKER_ROLE = keccak256("TICKER_ROLE");
    bytes32 public constant WHITELISTED_ROLE = keccak256("WHITELISTED_ROLE");

    // lower range level
    int24 public tickLower;
    // up range level
    int24 public tickUpper;

    int24 public tickSpacing;

    uint16 public managementFee;

    bool public paused;

    IVaultSwap vaultSwap;

    // The tokens that are being managed by the vault.
    IERC20 public token0;
    IERC20 public token1;

    IUniswapV3Pool public pool;

    address public manager;

    /// @param _pool Uniswap V3 pool for which liquidity is managed
    /// @param _manager Manager of the Vault
    /// @param _name, name of the pool
    /// @param _symbol, symbol of the share
    constructor(
        address _pool,
        address _manager,
        string memory _name,
        string memory _symbol,
        int24 _tickLower,
        int24 _tickUpper,
        uint16 _managementFee,
        IVaultSwap _vaultSwap
    ) ERC20Permit(_name) ERC20(_name, _symbol) {
        require(_pool != address(0));
        require(_manager != address(0));
        pool = IUniswapV3Pool(_pool);
        require(address(pool.token0()) != address(0));
        require(address(pool.token1()) != address(0));
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
        manager = _manager;
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        tickSpacing = pool.tickSpacing();
        managementFee = _managementFee;
        _setupRole(DEFAULT_ADMIN_ROLE, tx.origin);
        vaultSwap = _vaultSwap;
    }

    modifier unpaused() {
        require(!paused);
        _;
    }

    function deposit(
        uint256 _amount0,
        uint256 _amount1,
        IVaultSwap.SwapParams calldata swap0Params,
        IVaultSwap.SwapParams calldata swap1Params,
        address _from,
        address _to,
        uint256 _amount0Minimum,
        uint256 _amount1Minimum
    ) external payable nonReentrant unpaused returns (uint256 shares) {
        require(hasRole(WHITELISTED_ROLE, msg.sender));
        require(_from == msg.sender, "Invalid sender");
        if (_amount0 == 0 && _amount1 == 0) {
            if (_amount0 == 0) {
                _amount0 = _approveAndSwap(_from, swap0Params);
            }
            if (_amount1 == 0) {
                _amount1 = _approveAndSwap(_from, swap1Params);
            }
            shares = getShares(_amount0, _amount1, _amount0, _amount1); // Need to check the math
        } else if (_amount0 == 0 || _amount1 == 0) {
            if (_amount0 == 0) {
                _amount0 = _approveAndSwap(_from, swap0Params);
                token1.safeTransferFrom(_from, address(this), _amount1);
                shares = getShares(_amount0, _amount1, _amount0, 0); // Need to check the math
            } else {
                _amount1 = _approveAndSwap(_from, swap1Params);
                token0.safeTransferFrom(_from, address(this), _amount0);
                shares = getShares(_amount0, _amount1, 0, _amount1); // Need to check the math
            }
        } else {
            shares = getShares(_amount0, _amount1, 0, 0); // Need to check the math
            token0.safeTransferFrom(_from, address(this), _amount0);
            token1.safeTransferFrom(_from, address(this), _amount1);
        }

        uint128 _liquidity = VaultEnterpriseHelper.getLiquidityForAmounts(
            pool,
            tickLower,
            tickUpper,
            _amount0,
            _amount1
        );

        (uint256 _amount0Minted, uint256 _amount1Minted) = pool.mint(
            address(this),
            tickLower,
            tickUpper,
            _liquidity,
            abi.encode(_to)
        );

        require(
            _amount0Minted >= _amount0Minimum &&
                _amount1Minted >= _amount1Minimum,
            "Insufficient Liquidity"
        );
        _mint(_to, shares);

        emit Deposit(_to);
    }

    function _approveAndSwap(
        address _from,
        IVaultSwap.SwapParams calldata params
    ) internal returns (uint256 _amount) {
        params.sellToken.safeTransferFrom(
            _from,
            address(this),
            params.sellAmount
        );
        params.sellToken.approve(address(vaultSwap), params.sellAmount);
        _amount = vaultSwap.swap(params);
    }

    /// @param _shares Number of liquidity tokens to redeem as pool assets
    /// @param _to Address to which redeemed pool assets are sent
    /// @param _from Address from which liquidity tokens are sent
    /// @return _amount0 Amount of token0 redeemed by the submitted liquidity tokens
    /// @return _amount1 Amount of token1 redeemed by the submitted liquidity tokens
    function withdraw(
        uint256 _shares,
        address _to,
        address _from,
        uint256 _amount0Minimum,
        uint256 _amount1Minimum
    )
        external
        override
        nonReentrant
        unpaused
        returns (uint256 _amount0, uint256 _amount1)
    {
        require(hasRole(WHITELISTED_ROLE, msg.sender));
        require(_shares > 0, "Shares");
        require(balanceOf(_from) >= _shares, "Insufficient Balance");
        require(_from == msg.sender, "Invalid Sender");
        require(_to != address(0), "Invalid Reciever");

        collectPoolFees();

        (uint128 _position, , ) = VaultEnterpriseHelper.getPosition(
            pool,
            tickLower,
            tickUpper
        );
        uint128 _liquidityForShares = VaultEnterpriseHelper.safeUint128(
            uint256(_position).mul(_shares).div(totalSupply())
        );
        uint256 _returned0;
        uint256 _returned1;
        if (_liquidityForShares > 0) {
            (uint256 _owed0, uint256 _owed1) = pool.burn(
                tickLower,
                tickUpper,
                _liquidityForShares
            );
            require(
                _owed0 >= _amount0Minimum && _owed1 >= _amount1Minimum,
                "Insufficient Liquidity"
            );

            (_returned0, _returned1) = pool.collect(
                _to,
                tickLower,
                tickUpper,
                uint128(_owed0),
                uint128(_owed1)
            );
        }

        // Push tokens proportional to unused balances
        uint256 _availableAmount0 = token0
            .balanceOf(address(this))
            .mul(_shares)
            .div(totalSupply());
        uint256 _availableAmount1 = token1
            .balanceOf(address(this))
            .mul(_shares)
            .div(totalSupply());
        if (_availableAmount0 > 0) token0.safeTransfer(_to, _availableAmount0);
        if (_availableAmount1 > 0) token1.safeTransfer(_to, _availableAmount1);

        _amount0 = _returned0.add(_availableAmount0);
        _amount1 = _returned1.add(_availableAmount1);

        _burn(_from, _shares);

        emit Withdrawal(_from, _to, _shares, _amount0, _amount1);
    }

    /// @notice Compound pool fees and distribute management fees
    /// @return _amount0Minted Quantity of addition token0 minted in the pool
    /// @return _amount1Minted Quantity of addition token1 minted in the pool
    function compound()
        external
        override
        unpaused
        returns (uint256 _amount0Minted, uint256 _amount1Minted)
    {
        require(hasRole(COMPOUND_ROLE, msg.sender));
        (
            ,
            uint256 _token0Collected,
            uint256 _token1Collected
        ) = collectPoolFees();

        // Collect Management fees
        if (
            _token0Collected.div(managementFee) > 0 &&
            token0.balanceOf(address(this)) > 0
        )
            token0.safeTransfer(
                manager,
                FullMath.mulDiv(_token0Collected, managementFee, 10000)
            );
        if (
            _token1Collected.div(managementFee) > 0 &&
            token1.balanceOf(address(this)) > 0
        )
            token0.safeTransfer(
                manager,
                FullMath.mulDiv(_token0Collected, managementFee, 100)
            );

        uint128 _liquidity = VaultEnterpriseHelper.getLiquidityForAmounts(
            pool,
            tickLower,
            tickUpper,
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );

        (_amount0Minted, _amount1Minted) = pool.mint(
            address(this),
            tickLower,
            tickUpper,
            _liquidity,
            abi.encode(address(this))
        );
    }

    /// @param _tickLower The lower tick of the rebalanced position
    /// @param _tickUpper The upper tick of the rebalanced position
    function rebalance(
        int24 _tickLower,
        int24 _tickUpper
    ) external override nonReentrant unpaused {
        require(hasRole(TICKER_ROLE, msg.sender));
        require(
            _tickLower < _tickUpper &&
                _tickLower % tickSpacing == 0 &&
                _tickUpper % tickSpacing == 0
        );
        collectPoolFees();
        (
            uint128 _liquidityToCollect,
            uint128 _tokens0InPosition,
            uint128 _token1InPosition
        ) = VaultEnterpriseHelper.getPosition(pool, tickLower, tickUpper);

        uint256 _returned0;
        uint256 _returned1;
        if (_liquidityToCollect > 0) {
            (uint256 _owed0, uint256 _owed1) = pool.burn(
                tickLower,
                tickUpper,
                _liquidityToCollect
            );

            (_returned0, _returned1) = pool.collect(
                address(this),
                tickLower,
                tickUpper,
                VaultEnterpriseHelper.safeUint128(_owed0),
                VaultEnterpriseHelper.safeUint128(_owed1)
            );
        }

        (, int24 tick, , , , , ) = pool.slot0();

        emit Rebalance(
            tick,
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this)),
            _tokens0InPosition,
            _token1InPosition,
            totalSupply()
        );

        tickLower = _tickLower;
        tickUpper = _tickUpper;

        uint128 _liquidityToMint = VaultEnterpriseHelper.getLiquidityForAmounts(
            pool,
            tickLower,
            tickUpper,
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );

        pool.mint(
            address(this),
            tickLower,
            tickUpper,
            _liquidityToMint,
            abi.encode(address(this))
        );
    }

    function getShares(
        uint256 _amount0,
        uint256 _amount1,
        uint256 _adjustment0,
        uint256 _adjustment1
    ) internal view returns (uint256 _shares) {
        uint256 _price = VaultEnterpriseHelper.getPoolPrice(pool);
        (uint256 _totalAmount0, uint256 _totalAmount1) = VaultEnterpriseHelper
            .getPositionTotalAmounts(
                pool,
                tickLower,
                tickUpper,
                token0.balanceOf(address(this)) - _adjustment0,
                token1.balanceOf(address(this)) - _adjustment1
            );
        if (totalSupply() > 0) {
            _shares = FullMath.mulDiv(
                // totalDeposits
                (_amount0).add(_price.mul(_amount1)),
                totalSupply(),
                // totalAssets
                (_totalAmount0).add(_price.mul(_totalAmount1))
            );
        } else {
            _shares = _amount1.add(_amount0.mul(_price).div(1e18));
        }
    }

    /// @notice gets the User assets in the vault excluding non-compound fees
    /// @return _amount0ForShares Quantity of token0 owned by the user
    /// @return _amount1ForShares Quantity of token1 owned by the user
    function getUserPositionDetails(
        address _user
    )
        external
        view
        override
        returns (uint256 _amount0ForShares, uint256 _amount1ForShares)
    {
        (uint256 _amount0, uint256 _amount1) = VaultEnterpriseHelper
            .getPositionTotalAmounts(
                pool,
                tickLower,
                tickUpper,
                token0.balanceOf(address(this)),
                token1.balanceOf(address(this))
            );

        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            _amount0ForShares = uint128(
                uint256(_amount0).mul(balanceOf(_user)).div(_totalSupply)
            );
            _amount1ForShares = uint128(
                uint256(_amount1).mul(balanceOf(_user)).div(_totalSupply)
            );
        }
    }

    // function getUserPositionDetails(
    //     address _user
    // )
    //     external
    //     view
    //     override
    //     returns (uint256 _amount0ForShares, uint256 _amount1ForShares)
    // {
    //     (_amount0ForShares, _amount1ForShares) = VaultEnterpriseHelper
    //         .getUserPositionDetails(
    //             pool,
    //             tickLower,
    //             tickUpper,
    //             totalSupply(),
    //             _user,
    //             balanceOf(_user),
    //             address(this)
    //         );
    // }

    /// @notice Collect fees from the pool
    /// @return _liquidity Liquidity in the position
    /// @return _token0Collected Quantity of token0 collected from the pool
    /// @return _token1Collected Quantity of token1 collected from the pool
    function collectPoolFees()
        internal
        returns (
            uint128 _liquidity,
            uint256 _token0Collected,
            uint256 _token1Collected
        )
    {
        (_liquidity, , ) = VaultEnterpriseHelper.getPosition(
            pool,
            tickLower,
            tickUpper
        );

        if (_liquidity > 0) {
            pool.burn(tickLower, tickUpper, 0);
            (_token0Collected, _token1Collected) = pool.collect(
                address(this),
                tickLower,
                tickUpper,
                type(uint128).max,
                type(uint128).max
            );
            emit CollectPoolFees(_token0Collected, _token1Collected);
        }
    }

    /// @notice Callback function of uniswapV3Pool mint
    function uniswapV3MintCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external override {
        require(msg.sender == address(pool));

        if (_amount0 > 0) token0.safeTransfer(msg.sender, _amount0);
        if (_amount1 > 0) token1.safeTransfer(msg.sender, _amount1);
    }

    /// @notice set the management fee
    /// @param _managementFee New Fee
    function setManagementFee(uint16 _managementFee) external override {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        managementFee = _managementFee;
        emit SetFee(managementFee);
    }

    /// @notice pause or unpause the contract
    function togglePause() external override {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        paused = !paused;
        emit ToggledPauseStatus();
    }

    fallback() external payable {}

    receive() external payable {}
}

