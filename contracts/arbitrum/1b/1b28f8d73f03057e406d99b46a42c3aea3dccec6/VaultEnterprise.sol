// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;

import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./FullMath.sol";
import "./LiquidityAmounts.sol";
import "./ERC20Permit.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./ReentrancyGuard.sol";

import "./console.sol";

contract VaultEnterprise is ERC20Permit, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    // lower range level
    int24 public tickLower;
    // up range level
    int24 public tickUpper;

    int24 public tickSpacing;

    uint8 public managementFee;

    bool public paused;

    // The tokens that are being managed by the vault.
    IERC20 public token0;
    IERC20 public token1;

    IUniswapV3Pool pool;

    address public manager;

    event Deposit(address);
    event CollectPoolFees(uint256, uint256);
    event PausedContract();
    event Rebalance(int24, uint256, uint256, uint256, uint256, uint256);
    event SetFee(uint8);
    event SetManager(address);
    event Withdrawal(address, address, uint256, uint256, uint256);

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
        uint8 _managementFee
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
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only Manager");
        _;
    }

    function getPool() external view returns (IUniswapV3Pool) {
        return pool;
    }

    function deposit(
        uint256 _amount0,
        uint256 _amount1,
        address _from,
        address _to
    ) external payable nonReentrant returns (uint256 shares) {
        require(!paused, "Contract Paused");
        require(_from == msg.sender, "Invalid sender");
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        uint256 _price = getPoolPrice();
        (
            uint256 _totalAmount0,
            uint256 _totalAmount1
        ) = getPositionTotalAmounts();

        uint256 _totalShares = totalSupply();
        if (_totalShares > 0) {
            uint256 _totalDeposit = (_amount0).add(_price.mul(_amount1));
            uint256 _totalAssets = (_totalAmount0).add(
                _price.mul(_totalAmount1)
            );
            shares = FullMath.mulDiv(_totalDeposit, _totalShares, _totalAssets);
        } else {
            shares = _amount1.add(_amount0.mul(_price).div(1e18));
        }

        token0.safeTransferFrom(_from, address(this), _amount0);
        token1.safeTransferFrom(_from, address(this), _amount1);

        uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            _amount0,
            _amount1
        );

        pool.mint(
            address(this),
            tickLower,
            tickUpper,
            _liquidity,
            abi.encode(_from)
        );

        _mint(_to, shares);

        emit Deposit(_to);
    }

    /// @param _shares Number of liquidity tokens to redeem as pool assets
    /// @param _to Address to which redeemed pool assets are sent
    /// @param _from Address from which liquidity tokens are sent
    /// @return _amount0 Amount of token0 redeemed by the submitted liquidity tokens
    /// @return _amount1 Amount of token1 redeemed by the submitted liquidity tokens
    function withdraw(
        uint256 _shares,
        address _to,
        address _from
    ) external nonReentrant returns (uint256 _amount0, uint256 _amount1) {
        require(!paused, "Contract Paused");
        require(_shares > 0, "shares");
        require(balanceOf(_from) <= _shares, "Insufficient Balance");
        require(_from == msg.sender, "Invalid Sender");
        require(_to != address(0), "Invalie Reciever");

        collectPoolFees();

        (uint128 _position, , ) = getPosition();
        uint128 _liquidityForShares = uint128(
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

            (_returned0, _returned1) = pool.collect(
                _to,
                tickLower,
                tickUpper,
                // Need to check of overflow
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
    onlyManager
    returns (uint256 _amount0Minted, uint256 _amount1Minted)
    {
        require(!paused, "Contract Paused");
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
                FullMath.mulDiv(_token0Collected, managementFee, 100)
            );
        if (
            _token1Collected.div(managementFee) > 0 &&
            token1.balanceOf(address(this)) > 0
        )
            token0.safeTransfer(
                manager,
                FullMath.mulDiv(_token0Collected, managementFee, 100)
            );

        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );

        console.log(_liquidity);
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
    ) external nonReentrant onlyManager {
        require(!paused, "Contract Paused");
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
        ) = getPosition();

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
                // Need to check of overflow
                uint128(_owed0),
                uint128(_owed1)
            );
        }

        (uint160 _sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();

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

        uint128 _liquidityToMint = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
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

    /// @notice gets the User assets in the vault excluding non-compung fees
    /// @return _amount0ForShares Quantity of token0 owned by the user
    /// @return _amount1ForShares Quantity of token1 owned by the user
    function getUserPositionDetails(
        address _user
    )
    external
    view
    returns (uint256 _amount0ForShares, uint256 _amount1ForShares)
    {
        (uint256 _amount0, uint256 _amount1) = getPositionTotalAmounts();

        uint256 _shares = balanceOf(_user);
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            _amount0ForShares = uint128(
                uint256(_amount0).mul(_shares).div(_totalSupply)
            );
            _amount1ForShares = uint128(
                uint256(_amount1).mul(_shares).div(_totalSupply)
            );
        }
    }

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
        (_liquidity, , ) = getPosition();

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

    /// @notice get the TotalAmounts of token0 and token1 in the Vault
    /// @return _total0 Quantity of token0 in position and unused in the Vault
    /// @return _total1 Quantity of token1 in position and unused in the Vault
    function getPositionTotalAmounts()
    public
    view
    returns (uint256 _total0, uint256 _total1)
    {
        (, uint256 _amount0, uint256 _amount1) = getPositionAmounts();
        _total0 = token0.balanceOf(address(this)).add(_amount0);
        _total1 = token1.balanceOf(address(this)).add(_amount1);
    }

    /// @notice gets the liquidity and amounts of token 0 and 1 for the position
    /// @return _liquidity Amount of total liquidity in the base position
    /// @return _amount0 Estimated amount of token0 that could be collected by
    /// burning the base position
    /// @return _amount1 Estimated amount of token1 that could be collected by
    /// burning the base position
    function getPositionAmounts()
    public
    view
    returns (uint128 _liquidity, uint256 _amount0, uint256 _amount1)
    {
        (
            uint128 _liquidityInPosition,
            uint128 _tokens0InPosition,
            uint128 _tokens1InPosition
        ) = getPosition();
        (_amount0, _amount1) = getAmountsForLiquidity(_liquidityInPosition);
        _amount0 = _amount0.add(uint256(_tokens0InPosition));
        _amount1 = _amount1.add(uint256(_tokens1InPosition));
        _liquidity = _liquidityInPosition;
    }

    /// @notice Get the info of the given position
    /// @return _liquidity The amount of liquidity of the position
    /// @return _tokens0InPosition Amount of token0 owed
    /// @return _tokens1InPosition Amount of token1 owed
    function getPosition()
    internal
    view
    returns (
        uint128 _liquidity,
        uint128 _tokens0InPosition,
        uint128 _tokens1InPosition
    )
    {
        bytes32 _positionId = keccak256(
            abi.encodePacked(address(this), tickLower, tickUpper)
        );
        (_liquidity, , , _tokens0InPosition, _tokens1InPosition) = pool
        .positions(_positionId);
    }

    /// @notice Get the amounts of the given numbers of liquidity tokens
    /// @param _liquidity The amount of liquidity tokens
    /// @return Amount of token0 and token1
    function getAmountsForLiquidity(
        uint128 _liquidity
    ) internal view returns (uint256, uint256) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            _liquidity
        );
    }

    /**
     * @notice Gets latest Uniswap price in the pool, token1 represented in price of token0
     * @notice pool Address of the Uniswap V3 pool
     */
    function getPoolPrice() public view returns (uint256 _price) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        uint256 _priceX192 = uint256(_sqrtRatioX96).mul(_sqrtRatioX96);
        _price = FullMath.mulDiv(_priceX192, 1e18, 1 << 192);

        return _price;
    }

    /// @notice Callback function of uniswapV3Pool mint
    function uniswapV3MintCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external {
        require(msg.sender == address(pool));

        if (_amount0 > 0) token0.safeTransfer(msg.sender, _amount0);
        if (_amount1 > 0) token1.safeTransfer(msg.sender, _amount1);
    }

    /// @notice set the management fee
    /// @param _managementFee New Fee
    function setManagementFee(uint8 _managementFee) external onlyManager {
        managementFee = _managementFee;
        emit SetFee(managementFee);
    }

    /// @notice set the management manager
    /// @param _manager New manager
    function setManager(address _manager) external onlyManager {
        manager = _manager;
        emit SetManager(manager);
    }

    /// @notice pause or unpause the contract
    function togglePause() external onlyManager {
        paused = !paused;
        emit PausedContract();
    }
}

