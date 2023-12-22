// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

import "./IWETH.sol";
import "./IOneSplitWrap.sol";
import "./ERC20SafeUpgradeable.sol";
import "./IEthHandler.sol";

contract HandlerReserveUpgradeable is
    Initializable,
    ContextUpgradeable,
    AccessControlUpgradeable,
    ERC20SafeUpgradeable
{
    // token lp address => contract address
    mapping(address => address) public _lpToContract;

    // token contract address => lp address
    mapping(address => address) public _contractToLP;

    //Middleman for handling eth (Istanbul fix)
    IEthHandler private _ethHandler;

    function __HandlerReserveUpgradeable_init(address handler) internal initializer {
        __Context_init_unchained();
        __AccessControl_init();
        __ERC20SafeUpgradeable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ERC20HANDLER_ROLE, handler);
    }

    function __HandlerReserveUpgradeable_init_unchained() internal initializer {}

    function initialize(address handler) external initializer {
        __HandlerReserveUpgradeable_init(handler);
    }

    receive() external payable {}

    /// @dev Set the address of the ethHandler contract.
    /// @param ethHandler Address of the ethHandler contract.
    function setEthHandler(IEthHandler ethHandler) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ethHandler = ethHandler;
    }

    function giveAllowance(
        address token,
        address spender,
        uint256 amount
    ) external onlyRole(ERC20HANDLER_ROLE) {
        _safeApprove(token, spender, amount);
    }

    /// @notice Used to deduct fee from user
    /// @dev Can only be called by ERC20Handler contract
    /// @param feeTokenAddress Address of the fee token
    /// @param depositor Address of the depositor
    /// @param requiredFee Amount of fee to be deducted
    /// @param _isFeeEnabled true if fee is enabled
    /// @param _feeManager Address of the fee manager contract
    function deductFee(
        address feeTokenAddress,
        address depositor,
        uint256 requiredFee,
        bool _isFeeEnabled,
        address _feeManager
    ) external onlyRole(ERC20HANDLER_ROLE) {
        if (requiredFee > 0 && _isFeeEnabled) {
            lockERC20(feeTokenAddress, depositor, _feeManager, requiredFee);
        }
    }

    /// @notice Used to mint Wrapped ERC20 tokens
    /// @dev Can only be called by ERC20Handler contract
    /// @param tokenAddress Address of the ERC20 token for which wrapped token is to be minted
    /// @param recipient Address of the recipient
    /// @param amount Amount of tokens to be wrapped
    function mintWrappedERC20(
        address tokenAddress,
        address recipient,
        uint256 amount
    ) public onlyRole(ERC20HANDLER_ROLE) {
        require(_contractToLP[tokenAddress] != address(0), "ERC20Handler: Liquidity pool not found");
        mintERC20(_contractToLP[tokenAddress], recipient, amount);
    }

    /// @notice Used to stake ERC20 tokens into the LP.
    /// @dev Can only be called by ERC20Handler contract
    /// @param depositor Address of the depositor
    /// @param tokenAddress Address of the ERC20 token
    /// @param amount Amount of tokens to be staked
    function stake(
        address depositor,
        address tokenAddress,
        uint256 amount
    ) external virtual onlyRole(ERC20HANDLER_ROLE) {
        require(_contractToLP[tokenAddress] != address(0), "ERC20Handler: Liquidity pool not created");
        lockERC20(tokenAddress, depositor, address(this), amount);
        mintERC20(_contractToLP[tokenAddress], depositor, amount);
    }

    /// @notice Used to stake ETH tokens into the LP.
    /// @dev Can only be called by ERC20Handler contract
    /// @param depositor Address of the depositor
    /// @param tokenAddress Address of the ERC20 token
    /// @param amount Amount of tokens to be staked
    function stakeETH(
        address depositor,
        address tokenAddress,
        uint256 amount
    ) external virtual onlyRole(ERC20HANDLER_ROLE) {
        require(_contractToLP[tokenAddress] != address(0), "ERC20Handler: Liquidity pool not created");
        mintERC20(_contractToLP[tokenAddress], depositor, amount);
    }

    /// @notice Unstake the ERC20 tokens from LP.
    /// @dev Can only be called by ERC20Handler contract.
    /// @param unstaker Address of the account who is willing to unstake.
    /// @param tokenAddress staking token of which liquidity needs to be removed.
    /// @param amount Amount that needs to be unstaked.
    function unstake(
        address unstaker,
        address tokenAddress,
        uint256 amount
    ) external virtual onlyRole(ERC20HANDLER_ROLE) {
        require(_contractToLP[tokenAddress] != address(0), "ERC20Handler: Liquidity pool not created");
        burnERC20(_contractToLP[tokenAddress], unstaker, amount);
        releaseERC20(tokenAddress, unstaker, amount);
    }

    /// @notice Unstake the ETH tokens from LP.
    /// @dev Can only be called by ERC20Handler contract.
    /// @param unstaker Address of the account who is willing to unstake.
    /// @param tokenAddress staking token of which liquidity needs to be removed.
    /// @param amount Amount that needs to be unstaked.
    /// @param WETH Address of WETH
    function unstakeETH(
        address unstaker,
        address tokenAddress,
        uint256 amount,
        address WETH
    ) external virtual onlyRole(ERC20HANDLER_ROLE) {
        require(_contractToLP[tokenAddress] != address(0), "ERC20Handler: Liquidity pool not created");
        burnERC20(_contractToLP[tokenAddress], unstaker, amount);

        IWETH(WETH).transfer(address(_ethHandler), amount);
        _ethHandler.withdraw(WETH, amount);
        safeTransferETH(unstaker, amount);
    }

    /// @notice Fetched staking record.
    /// @param account Address of the account whose record is fetched.
    /// @param tokenAddress staking token of which liquidity needs to be removed.
    function getStakedRecord(address account, address tokenAddress) external view virtual returns (uint256) {
        if (_contractToLP[tokenAddress] != address(0)) {
            return RouterERC20UpgradableToken(_contractToLP[tokenAddress]).balanceOf(account);
        }
        return 0;
    }

    /// @notice Withdraws EthToken from the contract.
    /// @dev Can only be called by ERC20Handler contract
    /// @param WETH Address of WETH
    /// @param amount Amount of tokens to be withdrawn
    function withdrawWETH(address WETH, uint256 amount) external onlyRole(ERC20HANDLER_ROLE) {
        IWETH(WETH).transfer(address(_ethHandler), amount);
        _ethHandler.withdraw(WETH, amount);
    }

    /// @notice Sets liquidity pool owner for an existing LP.
    /// @dev Can only be set by the ERC20Handler contract
    /// @param oldOwner Address of the old owner of LP
    /// @param newOwner Address of the new owner for LP
    /// @param tokenAddress Address of ERC20 token
    /// @param lpAddress Address of LP.
    function _setLiquidityPoolOwner(
        address oldOwner,
        address newOwner,
        address tokenAddress,
        address lpAddress
    ) external virtual onlyRole(ERC20HANDLER_ROLE) {
        require(newOwner != address(0), "ERC20Handler: new owner cannot be null");
        require(tokenAddress != address(0), "ERC20Handler: tokenAddress cannot be null");
        require(lpAddress != address(0), "ERC20Handler: lpAddress cannot be null");

        RouterERC20UpgradableToken token = RouterERC20UpgradableToken(lpAddress);
        _lpToContract[lpAddress] = tokenAddress;
        _contractToLP[tokenAddress] = lpAddress;
        require(token.hasRole(DEFAULT_ADMIN_ROLE, oldOwner), "Old owner address is wrong");
        token.revokeRole(DEFAULT_ADMIN_ROLE, oldOwner);
        token.grantRole(DEFAULT_ADMIN_ROLE, newOwner);
    }

    /// @notice Sets liquidity pool for given ERC20 address. These pools will be used to
    /// stake and unstake liqudity.
    /// @dev Can only be set by the ERC20Handler contract.
    // / @param name Name of the LP token.
    // / @param symbol Symbol for LP token.
    // / @param decimals Decimal for LP token.
    /// @param contractAddress Address of contract for which LP contract should be created.
    /// @param lpAddress Address of LP contract.
    function _setLiquidityPool(
        // string memory name,
        // string memory symbol,
        // uint8 decimals,
        address contractAddress,
        address lpAddress
    ) external virtual onlyRole(ERC20HANDLER_ROLE) returns (address) {
        require(_contractToLP[contractAddress] == address(0), "ERC20Handler: pool already deployed");

        // address newLPAddress;
        // if (lpAddress == address(0)) {
        //     RouterERC20Upgradable newLPAddr = new RouterERC20Upgradable(name, symbol, decimals);
        //     newLPAddress = address(newLPAddr);
        // } else {
        //     newLPAddress = lpAddress;
        // }
        // _lpToContract[newLPAddress] = contractAddress;
        // _contractToLP[contractAddress] = newLPAddress;
        // return newLPAddress;
        _lpToContract[lpAddress] = contractAddress;
        _contractToLP[contractAddress] = lpAddress;
        return lpAddress;
    }

    /// @notice Sets liquidity pool for given ERC20 address. These pools will be used to
    /// stake and unstake liqudity.
    /// @dev Can only be set by the DEFAULT_ADMIN address.
    // / @param name Name of the LP token.
    // / @param symbol Symbol for LP token.
    // / @param decimals Decimal for LP token.
    /// @param contractAddress Address of contract for which LP contract should be created.
    /// @param lpAddress Address of LP contract.
    function _resetLiquidityPool(
        // string memory name,
        // string memory symbol,
        // uint8 decimals,
        address contractAddress,
        address lpAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // address newLPAddress;
        // if (lpAddress == address(0)) {
        //     RouterERC20Upgradable newLPAddr = new RouterERC20Upgradable(name, symbol, decimals);
        //     newLPAddress = address(newLPAddr);
        // } else {
        //     newLPAddress = lpAddress;
        // }
        // _lpToContract[newLPAddress] = contractAddress;
        // _contractToLP[contractAddress] = newLPAddress;
        // return newLPAddress;
        _lpToContract[lpAddress] = address(0);
        _contractToLP[contractAddress] = address(0);
    }

    /// @notice Used to reset the LP.
    /// @dev Can only be called by the default admin.
    /// @param contractAddress Address of contract for which LP contract should be reset.
    /// @param lpAddress Address of LP contract.
    function resetLP(address contractAddress, address lpAddress) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _lpToContract[lpAddress] = address(0);
        _contractToLP[contractAddress] = address(0);
    }

    /// @notice Swaps ERC20 tokens.
    /// @dev Can only be set by the ERC20Handler contract
    /// @param oneSplitAddress Address of the OneSplit contract.
    /// @param fromToken Token to be swapped from.
    /// @param destToken Token to be swapped to.
    /// @param amount Amount of token to be swapped.
    /// @param minReturn Minimum return of destination token after swap.
    /// @param flags Identifier for the DEX.
    /// @param dataTx Data passed by Relayer for the tx.
    function swap(
        address oneSplitAddress,
        address fromToken,
        address destToken,
        uint256 amount,
        uint256 minReturn,
        uint256 flags,
        bytes memory dataTx
    ) external onlyRole(ERC20HANDLER_ROLE) returns (uint256 returnAmount) {
        IOneSplitWrap oneSplitWrap = IOneSplitWrap(oneSplitAddress);
        returnAmount = oneSplitWrap.swap(fromToken, destToken, amount, minReturn, flags, dataTx, true);
        return returnAmount;
    }

    /// @notice Swaps multiple ERC20 tokens to reach a destination token.
    /// @dev Can only be set by the ERC20Handler contract
    /// @param oneSplitAddress Address of the OneSplit contract.
    /// @param tokens Token to be hopped between from and to tokens.
    /// @param amount Amount of token to be swapped.
    /// @param minReturn Minimum return of destination token after swap.
    /// @param flags Identifier for the DEX.
    /// @param dataTx Data passed by Relayer for the tx.
    function swapMulti(
        address oneSplitAddress,
        address[] memory tokens,
        uint256 amount,
        uint256 minReturn,
        uint256[] memory flags,
        bytes[] memory dataTx
    ) external onlyRole(ERC20HANDLER_ROLE) returns (uint256 returnAmount) {
        IOneSplitWrap oneSplitWrap = IOneSplitWrap(oneSplitAddress);
        returnAmount = oneSplitWrap.swapMulti(tokens, amount, minReturn, flags, dataTx, true);
        return returnAmount;
    }

    /// @notice Get expected return ERC20 token swap.
    /// @param oneSplitAddress Address of the OneSplit contract.
    /// @param fromToken Token to be swapped from.
    /// @param toToken Token to be swapped to.
    /// @param amount Amount of token to be swapped.
    /// @param parts Parts data required to calculate min return.
    /// @param flags Identifier for the DEX.
    function getExpectedReturn(
        address oneSplitAddress,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 parts,
        uint256 flags
    ) public view virtual returns (uint256 returnAmount, uint256[] memory distribution) {
        IOneSplitWrap oneSplitWrap = IOneSplitWrap(oneSplitAddress);
        return oneSplitWrap.getExpectedReturn(fromToken, toToken, amount, parts, flags);
    }

    /// @notice Get expected return ERC20 token swap with Gas amount.
    /// @param oneSplitAddress Address of the OneSplit contract.
    /// @param fromToken Token to be swapped from.
    /// @param toToken Token to be swapped to.
    /// @param amount Amount of token to be swapped.
    /// @param parts Parts data required to calculate min return.
    /// @param flags Identifier for the DEX.
    /// @param toTokenEthPriceTimesGasPrice Gas for desination token.
    function getExpectedReturnWithGas(
        address oneSplitAddress,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 parts,
        uint256 flags,
        uint256 toTokenEthPriceTimesGasPrice
    )
        public
        view
        virtual
        returns (
            uint256 returnAmount,
            uint256 estimateGasAmount,
            uint256[] memory distribution
        )
    {
        IOneSplitWrap oneSplitWrap = IOneSplitWrap(oneSplitAddress);
        return
            oneSplitWrap.getExpectedReturnWithGas(
                fromToken,
                toToken,
                amount,
                parts,
                flags,
                toTokenEthPriceTimesGasPrice
            );
    }

    /// @notice Get expected return multi ERC20 token swap with Gas amount.
    /// @param oneSplitAddress Address of the OneSplit contract.
    /// @param tokens Token to be hopped between from and to tokens.
    /// @param amount Amount of token to be swapped.
    /// @param parts Parts data required to calculate min return.
    /// @param flags Identifiers for the DEX.
    /// @param destTokenEthPriceTimesGasPrices Gas for desination token.
    function getExpectedReturnWithGasMulti(
        address oneSplitAddress,
        address[] memory tokens,
        uint256 amount,
        uint256[] memory parts,
        uint256[] memory flags,
        uint256[] memory destTokenEthPriceTimesGasPrices
    )
        public
        view
        virtual
        returns (
            uint256[] memory returnAmounts,
            uint256 estimateGasAmount,
            uint256[] memory distribution
        )
    {
        IOneSplitWrap oneSplitWrap = IOneSplitWrap(oneSplitAddress);
        return
            oneSplitWrap.getExpectedReturnWithGasMulti(tokens, amount, parts, flags, destTokenEthPriceTimesGasPrices);
    }
}

