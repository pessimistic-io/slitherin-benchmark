// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./ERC20_IERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

import {IDnGmxJuniorVault} from "./IDnGmxJuniorVault.sol";
import {IDnGmxBatchingManager} from "./IDnGmxBatchingManager.sol";
import {IVault} from "./IVault.sol";
import {DepositPeriphery} from "./DepositPeriphery.sol";

import {IQuoter} from "./IQuoter.sol";

import {IDnGmxRouter} from "./IDnGmxRouter.sol";
import {IJITManager} from "./IJITManager.sol";

import {console} from "./console.sol";

contract DnGmxRouter is IDnGmxRouter, OwnableUpgradeable {
    IDnGmxJuniorVault public dnGmxJuniorVault;
    IDnGmxBatchingManager public dnGmxBatchingManager;
    DepositPeriphery public depositPeriphery;

    IVault public gmxVault;

    IJITManager public jitManager1;
    IJITManager public jitManager2;

    IERC20 public sGLP;
    IQuoter public quoterV1;

    address public weth;
    address public wbtc;
    address public usdc;

    address public batchingManagerKeeper;

    modifier insideJIT() {
        _addLiquidity();
        _;
        _removeLiquidty();
    }

    modifier onlyBatchingManagerKeeper() {
        require(
            msg.sender == batchingManagerKeeper,
            "DnGmxRouter: not batching manager keeper"
        );
        _;
    }

    function initialize(
        IDnGmxJuniorVault _dnGmxJuniorVault,
        IDnGmxBatchingManager _dnGmxBatchingManager,
        DepositPeriphery _depositPeriphery,
        IVault _gmxVault,
        IJITManager _jitManager1,
        IJITManager _jitManager2,
        IQuoter _quoterV1,
        IERC20 _sGLP,
        address _weth,
        address _wbtc,
        address _usdc
    ) external initializer {
        __Ownable_init();

        dnGmxJuniorVault = _dnGmxJuniorVault;
        dnGmxBatchingManager = _dnGmxBatchingManager;
        depositPeriphery = _depositPeriphery;
        gmxVault = _gmxVault;
        jitManager1 = _jitManager1;
        jitManager2 = _jitManager2;
        quoterV1 = _quoterV1;
        sGLP = _sGLP;
        weth = _weth;
        wbtc = _wbtc;
        usdc = _usdc;

        sGLP.approve(address(dnGmxJuniorVault), type(uint).max);
    }

    function setBatchingManagerKeeper(address _bmKeeper) external onlyOwner {
        batchingManagerKeeper = _bmKeeper;
    }

    function deposit(
        uint256 amount,
        address receiver
    ) external insideJIT returns (uint256 shares) {
        sGLP.transferFrom(msg.sender, address(this), amount);
        shares = dnGmxJuniorVault.deposit(amount, receiver);
    }

    /// @notice allows to use tokens to deposit into junior vault using JIT router
    /// @param token input token
    /// @param receiver address of the receiver
    /// @param tokenAmount amount of token to deposit
    /// @return sharesReceived shares received in exchange of token
    function depositToken(
        address token,
        address receiver,
        uint256 tokenAmount
    ) external returns (uint256 sharesReceived) {
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        IERC20(token).approve(address(depositPeriphery), tokenAmount);
        sharesReceived = depositPeriphery.depositToken(
            token,
            receiver,
            tokenAmount
        );
    }

    function executeBatchStake() external onlyBatchingManagerKeeper {
        dnGmxBatchingManager.executeBatchStake();
    }

    function executeBatchDeposit(
        uint256 amount
    ) external onlyBatchingManagerKeeper insideJIT {
        dnGmxBatchingManager.executeBatchDeposit(amount);
    }

    function getQuotes(
        uint256 assets
    )
        external
        returns (
            uint ethQuoteWithoutJIT,
            uint btcQuoteWithoutJIT,
            uint ethQuoteWithJIT,
            uint btcQuoteWithJIT
        )
    {
        (ethQuoteWithoutJIT, btcQuoteWithoutJIT) = _getQuotes(assets);
        (, bytes memory revertData) = address(this).call(
            abi.encodeWithSelector(this.getQuotesJitRevert.selector, assets)
        );

        (ethQuoteWithJIT, btcQuoteWithJIT) = abi.decode(
            revertData,
            (uint, uint)
        );
    }

    function getQuotesJitRevert(uint256 assets) external {
        _addLiquidity();
        (uint ethQuote, uint btcQuote) = _getQuotes(assets);
        bytes memory revertData = abi.encode(ethQuote, btcQuote);
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }

    function _getQuotes(
        uint assets
    ) internal returns (uint ethQuote, uint btcQuote) {
        uint priceX128 = dnGmxJuniorVault.getPriceX128();
        uint dollarValueD6 = (priceX128 * assets) >> 128;
        uint totalWeights = gmxVault.totalTokenWeights();
        uint ethWeight = gmxVault.tokenWeights(weth);
        uint btcWeight = gmxVault.tokenWeights(wbtc);
        uint ethDollars = (dollarValueD6 * ethWeight) / totalWeights;
        uint btcDollars = (dollarValueD6 * btcWeight) / totalWeights;
        ethQuote = quoterV1.quoteExactOutput(
            abi.encodePacked(usdc, uint24(500), weth),
            ethDollars
        );
        btcQuote = quoterV1.quoteExactOutput(
            abi.encodePacked(usdc, uint24(500), weth, uint24(500), wbtc),
            btcDollars
        );
    }

    function _addLiquidity() internal {
        jitManager1.addLiquidity(false);
        jitManager2.addLiquidity(false);
    }

    function _removeLiquidty() internal {
        jitManager1.removeLiquidity();
        jitManager2.removeLiquidity();
    }
}

