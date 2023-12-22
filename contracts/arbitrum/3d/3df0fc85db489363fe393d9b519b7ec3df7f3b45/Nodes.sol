// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./Initializable.sol";
import "./IUniswapV2Pair.sol";
import "./Babylonian.sol";
import "./IUniswapV2Factory.sol";
import "./AddressToUintIterableMap.sol";
import "./ITortleVault.sol";
import "./SafeERC20.sol";
import "./IWETH.sol";
import "./SwapsUni.sol";
import "./SelectSwapRoute.sol";
import "./SelectLPRoute.sol";
import "./SelectNestedRoute.sol";
import "./Batch.sol";

error Nodes__InsufficientBalance();
error Nodes__EmptyArray();
error Nodes__InvalidArrayLength();
error Nodes__TransferFailed();
error Nodes__DepositOnLPInvalidLPToken();
error Nodes__DepositOnLPInsufficientT0Funds();
error Nodes__DepositOnLPInsufficientT1Funds();
error Nodes__DepositOnNestedStrategyInsufficientFunds();
error Nodes__WithdrawFromNestedStrategyInsufficientShares();
error Nodes__DepositOnFarmTokensInsufficientT0Funds();
error Nodes__DepositOnFarmTokensInsufficientT1Funds();
error Nodes__WithdrawFromLPInsufficientFunds();
error Nodes__WithdrawFromFarmInsufficientFunds();

contract Nodes is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using AddressToUintIterableMap for AddressToUintIterableMap.Map;

    address public owner;
    address public tortleDojos;
    address public tortleTreasury;
    address public tortleDevFund;
    SwapsUni public swapsUni;
    SelectSwapRoute public selectSwapRoute;
    SelectLPRoute public selectLPRoute;
    SelectNestedRoute public selectNestedRoute;
    Batch private batch;
    address private WFTM;
    address public usdc;

    uint8 public constant INITIAL_TOTAL_FEE = 50; // 0.50%
    uint16 public constant PERFORMANCE_TOTAL_FEE = 500; // 5%
    uint16 public constant DOJOS_FEE = 3333; // 33.33%
    uint16 public constant TREASURY_FEE = 4666; // 46.66%
    uint16 public constant DEV_FUND_FEE = 2000; // 20%

    mapping(address => AddressToUintIterableMap.Map) private balance;

    event AddFunds(address tokenInput, uint256 amount);
    event AddFundsForFTM(string indexed recipeId, address tokenInput, uint256 amount);
    event Swap(address tokenInput, uint256 amountIn, address tokenOutput, uint256 amountOut);
    event Split(address tokenOutput1, uint256 amountOutToken1, address tokenOutput2, uint256 amountOutToken2);
    event DepositOnLP(uint256 lpAmount);
    event WithdrawFromLP(uint256 amountTokenDesired);
    event DepositOnNestedStrategy(address vaultAddress, uint256 sharesAmount);
    event WithdrawFromNestedStrategy(address tokenOut, uint256 amountTokenDesired);
    event DepositOnFarm(uint256 ttAmount, uint256 lpBalance);
    event WithdrawFromFarm(address tokenDesided, uint256 amountTokenDesired, uint256 rewardAmount);
    event Liquidate(address tokenOutput, uint256 amountOut);
    event SendToWallet(address tokenOutput, uint256 amountOut);
    event RecoverAll(address tokenOut, uint256 amountOut);

    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == address(batch) || msg.sender == address(this), 'You must be the owner.');
        _;
    }

    function initializeConstructor(
        address owner_,
        SwapsUni swapsUni_,
        SelectSwapRoute selectSwapRoute_,
        SelectLPRoute selectLPRoute_,
        SelectNestedRoute selectNestedRoute_,
        Batch batch_,
        address tortleDojos_,
        address tortleTrasury_,
        address tortleDevFund_,
        address wftm_,
        address usdc_
    ) public initializer {
        owner = owner_;
        swapsUni = swapsUni_;
        selectSwapRoute = selectSwapRoute_;
        selectLPRoute = selectLPRoute_;
        selectNestedRoute = selectNestedRoute_;
        batch = batch_;
        tortleDojos = tortleDojos_;
        tortleTreasury = tortleTrasury_;
        tortleDevFund = tortleDevFund_;
        WFTM = wftm_;
        usdc = usdc_;
    }

    function setBatch(Batch batch_) public onlyOwner {
        batch = batch_;
    }

    function setSwapsUni(SwapsUni swapsUni_) public onlyOwner {
        swapsUni = swapsUni_;
    }

    function setSelectSwapRoute(SelectSwapRoute selectSwapRoute_) public onlyOwner {
        selectSwapRoute = selectSwapRoute_;
    }

    function setSelectLPRoute(SelectLPRoute selectLPRoute_) public onlyOwner {
        selectLPRoute = selectLPRoute_;
    }

    function setSelectNestedRoute(SelectNestedRoute selectNestedRoute_) public onlyOwner {
        selectNestedRoute = selectNestedRoute_;
    }

    function setTortleDojos(address tortleDojos_) public onlyOwner {
        tortleDojos = tortleDojos_;
    }

    function setTortleTreasury(address tortleTreasury_) public onlyOwner {
        tortleTreasury = tortleTreasury_;
    }

    function setTortleDevFund(address tortleDevFund_) public onlyOwner {
        tortleDevFund = tortleDevFund_;
    }

    /**
    * @notice Function used to charge the correspoding fees (returns the amount - fees).
    * @param tokens_ Addresses of the tokens used as fees.
    * @param amount_ Amount of the token that is wanted to calculate its fees.
    * @param feeAmount_ Percentage of fees to be charged.
    */
    function _chargeFees(
        address user_,
        IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        uint256 feeAmount_,
        uint8 provider_,
        BatchSwapStep[] memory batchSwapStep_
    ) private returns (uint256) {
        uint256 amountFee_ = mulScale(amount_, feeAmount_, 10000);
        uint256 dojosTokens_;
        uint256 treasuryTokens_;
        uint256 devFundTokens_;

        if (address(tokens_[0]) == usdc) {
            dojosTokens_ = mulScale(amountFee_, DOJOS_FEE, 10000);
            treasuryTokens_ = mulScale(amountFee_, TREASURY_FEE, 10000);
            devFundTokens_ = mulScale(amountFee_, DEV_FUND_FEE, 10000);
        } else {
            increaseBalance(user_, address(tokens_[0]), amountFee_);
            uint256 amountSwap_ = swapTokens(user_, provider_, tokens_, amountFee_, amountOutMin_, batchSwapStep_);
            decreaseBalance(user_, address(tokens_[tokens_.length - 1]), amountSwap_);
            dojosTokens_ = amountSwap_ / 3;
            treasuryTokens_ = mulScale(amountSwap_, 2000, 10000);
            devFundTokens_= amountSwap_ - (dojosTokens_ + treasuryTokens_);
        }

        IERC20(usdc).safeTransfer(tortleDojos, dojosTokens_);
        IERC20(usdc).safeTransfer(tortleTreasury, treasuryTokens_);
        IERC20(usdc).safeTransfer(tortleDevFund, devFundTokens_);

        return amount_ - amountFee_;
    }

    function _chargeFeesForWFTM(uint256 amount_) private returns (uint256) {
        uint256 amountFee_ = mulScale(amount_, INITIAL_TOTAL_FEE, 10000);

        _approve(WFTM, address(swapsUni), amountFee_);
        uint256 _amountSwap = swapsUni.swapTokens(WFTM, amountFee_, usdc, 0);

        uint256 dojosTokens_ = _amountSwap / 3;
        uint256 treasuryTokens_ = mulScale(_amountSwap, 2000, 10000);
        uint256 devFundTokens_= _amountSwap - (dojosTokens_ + treasuryTokens_);

        IERC20(usdc).safeTransfer(tortleDojos, dojosTokens_);
        IERC20(usdc).safeTransfer(tortleTreasury, treasuryTokens_);
        IERC20(usdc).safeTransfer(tortleDevFund, devFundTokens_);

        return amount_ - amountFee_;
    }

    /**
     * @notice Function that allows to add funds to the contract to execute the recipes.
     * @param user_ Address of the user who will deposit the tokens.
     * @param tokens_ Addresses of the tokens to be deposited.
     * @param amount_ Amount of tokens to be deposited.
     */
    function addFundsForTokens(
        address user_,
        IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        uint8 provider_,
        BatchSwapStep[] memory batchSwapStep_
    ) public nonReentrant returns (uint256 amount) {
        if (amount_ <= 0) revert Nodes__InsufficientBalance();

        address tokenIn_ = address(tokens_[0]);

        uint256 balanceBefore = IERC20(tokenIn_).balanceOf(address(this));
        IERC20(tokenIn_).safeTransferFrom(user_, address(this), amount_);
        uint256 balanceAfter = IERC20(tokenIn_).balanceOf(address(this));
        if (balanceAfter <= balanceBefore) revert Nodes__TransferFailed();

        amount = _chargeFees(user_, tokens_, balanceAfter - balanceBefore, amountOutMin_, INITIAL_TOTAL_FEE, provider_, batchSwapStep_);
        increaseBalance(user_, tokenIn_, amount);

        emit AddFunds(tokenIn_, amount);
    }

    /**
    * @notice Function that allows to add funds to the contract to execute the recipes.
    * @param user_ Address of the user who will deposit the tokens.
    */
    function addFundsForFTM(address user_, string memory recipeId_) public payable nonReentrant returns (address token, uint256 amount) {
        if (msg.value <= 0) revert Nodes__InsufficientBalance();

        IWETH(WFTM).deposit{value: msg.value}();

        uint256 amount_ = _chargeFeesForWFTM(msg.value);
        increaseBalance(user_, WFTM, amount_);

        emit AddFundsForFTM(recipeId_, WFTM, amount_);
        return (WFTM, amount_);
    }

    /**
     * @notice Function that allows to send X amount of tokens and returns the token you want.
     * @param user_ Address of the user running the node.
     * @param provider_ Provider used for swapping tokens.
     * @param tokens_ Array of tokens to be swapped.
     * @param amount_ Amount of Tokens to be swapped.
     * @param amountOutMin_ Minimum amounts you want to use.
     * @param batchSwapStep_ Array of structs required by beets provider.
     */
    function swapTokens(
        address user_,
        uint8 provider_,
        IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        BatchSwapStep[] memory batchSwapStep_
    ) public onlyOwner returns (uint256 amountOut) {
        address tokenIn_ = address(tokens_[0]);
        address tokenOut_ = address(tokens_[tokens_.length - 1]);

        uint256 _userBalance = getBalance(user_, IERC20(tokenIn_));
        if (amount_ > _userBalance) revert Nodes__InsufficientBalance();

        if (tokenIn_ != tokenOut_) {
            _approve(tokenIn_, address(selectSwapRoute), amount_);
            amountOut = selectSwapRoute.swapTokens(tokens_, amount_, amountOutMin_, batchSwapStep_, provider_);

            decreaseBalance(user_, tokenIn_, amount_);
            increaseBalance(user_, tokenOut_, amountOut);
        } else amountOut = amount_;

        emit Swap(tokenIn_, amount_, tokenOut_, amountOut);
    }

    /**
    * @notice Function that divides the token you send into two tokens according to the percentage you select.
    * @param args_ user, firstTokens, secondTokens, amount, percentageFirstToken, amountOutMinFirst_, amountOutMinSecond_, providers, batchSwapStepFirstToken, batchSwapStepSecondToken.
    */
    function split(
        bytes calldata args_,
        BatchSwapStep[] memory batchSwapStepFirstToken_,
        BatchSwapStep[] memory batchSwapStepSecondToken_
    ) public onlyOwner returns (uint256[] memory amountOutTokens) {
        (address user_, 
        IAsset[] memory firstTokens_, 
        IAsset[] memory secondTokens_, 
        uint256 amount_,
        uint256[] memory percentageAndAmountsOutMin_,
        uint8[] memory providers_
        ) = abi.decode(args_, (address, IAsset[], IAsset[], uint256, uint256[], uint8[]));

        if (amount_ > getBalance(user_, IERC20(address(firstTokens_[0])))) revert Nodes__InsufficientBalance();

        uint256 firstTokenAmount_ = mulScale(amount_, percentageAndAmountsOutMin_[0], 10000);
        
        amountOutTokens = new uint256[](2);
        amountOutTokens[0] = swapTokens(user_, providers_[0], firstTokens_, firstTokenAmount_, percentageAndAmountsOutMin_[1], batchSwapStepFirstToken_);
        amountOutTokens[1] = swapTokens(user_, providers_[1], secondTokens_, (amount_ - firstTokenAmount_), percentageAndAmountsOutMin_[2], batchSwapStepSecondToken_);

        emit Split(address(firstTokens_[firstTokens_.length - 1]), amountOutTokens[0], address(secondTokens_[secondTokens_.length - 1]), amountOutTokens[1]);
    }

    /**
    * @notice Function used to deposit tokens on a lpPool and get lptoken
    * @param user_ Address of the user.
    * @param poolId_ Beets pool id.
    * @param lpToken_ Address of the lpToken.
    * @param tokens_ Addresses of tokens that are going to be deposited.
    * @param amounts_ Amounts of tokens.
    * @param amountOutMin0_ Minimum amount of token0.
    * @param amountOutMin0_ Minimum amount of token1.
    */
    function depositOnLp(
        address user_,
        bytes32 poolId_,
        address lpToken_,
        uint8 provider_,
        address[] memory tokens_,
        uint256[] memory amounts_,
        uint256 amountOutMin0_,
        uint256 amountOutMin1_
    ) external nonReentrant onlyOwner returns (uint256 lpAmount) {

        for (uint8 i = 0; i < tokens_.length; i++) {
            if (amounts_[i] > getBalance(user_, IERC20(tokens_[i]))) revert Nodes__DepositOnLPInsufficientT0Funds();
            _approve(tokens_[i], address(selectLPRoute), amounts_[i]);
        }

        (uint256[] memory amountsOut, uint256 amountIn, address lpToken, uint256 numTokensOut) = selectLPRoute.depositOnLP(poolId_, lpToken_, provider_, tokens_, amounts_, amountOutMin0_, amountOutMin1_);

        for (uint8 i = 0; i < numTokensOut; i++) {
            decreaseBalance(user_, tokens_[i], amountsOut[i]);
            increaseBalance(user_, lpToken, amountIn);
        }
        lpAmount = amountIn;
        emit DepositOnLP(lpAmount);
    }

    /**
    * @notice Function used to withdraw tokens from a LPfarm
    * @param user_ Address of the user.
    * @param poolId_ Beets pool id.
    * @param lpToken_ Address of the lpToken.
    * @param tokens_ Addresses of tokens that are going to be deposited.
    * @param amountsOutMin_ Minimum amounts to be withdrawed.
    * @param amount_ Amount of LPTokens desired to withdraw.
    */
    function withdrawFromLp(
        address user_,
        bytes32 poolId_,
        address lpToken_,
        uint8 provider_,
        address[] memory tokens_,
        uint256[] memory amountsOutMin_,
        uint256 amount_
    ) external nonReentrant onlyOwner returns (uint256 amountTokenDesired) {

        if (amount_ > getBalance(user_, IERC20(lpToken_))) revert Nodes__WithdrawFromLPInsufficientFunds(); // check what to do with bp token
        _approve(lpToken_, address(selectLPRoute), amount_);

        address tokenDesired;
        (tokenDesired, amountTokenDesired) = selectLPRoute.withdrawFromLp(poolId_, lpToken_, provider_, tokens_, amountsOutMin_, amount_);

        decreaseBalance(user_, lpToken_, amount_);
        increaseBalance(user_, tokenDesired, amountTokenDesired);

        emit WithdrawFromLP(amountTokenDesired);
    }

    /**
    * @notice Function used to withdraw tokens from a LPfarm
    * @param user_ Address of the user.
    * @param token_ Input token to deposit on the vault
    * @param vaultAddress_ Address of the vault.
    * @param amount_ Amount of LPTokens desired to withdraw.
    * @param provider_ Type of Nested strategies.
    */
    function depositOnNestedStrategy(
        address user_,
        address token_, 
        address vaultAddress_, 
        uint256 amount_,
        uint8 provider_
    ) external nonReentrant onlyOwner returns (uint256 sharesAmount) {
        if (amount_ > getBalance(user_, IERC20(token_))) revert Nodes__DepositOnNestedStrategyInsufficientFunds();

        _approve(token_, address(selectNestedRoute), amount_);
        sharesAmount = selectNestedRoute.deposit(user_, token_, vaultAddress_, amount_, provider_);

        decreaseBalance(user_, token_, amount_);
        increaseBalance(user_, vaultAddress_, sharesAmount);

        emit DepositOnNestedStrategy(vaultAddress_, sharesAmount);
    }

    /**
    * @notice Function used to withdraw tokens from a LPfarm
    * @param user_ Address of the user.
    * @param tokenOut_ Output token to withdraw from the vault
    * @param vaultAddress_ Address of the vault.
    * @param sharesAmount_ Amount of Vault share tokens desired to withdraw.
    * @param provider_ Type of Nested strategies.
    */
    function withdrawFromNestedStrategy(
        address user_,
        address tokenOut_, 
        address vaultAddress_, 
        uint256 sharesAmount_,
        uint8 provider_
    ) external nonReentrant onlyOwner returns (uint256 amountTokenDesired) {
        if (sharesAmount_ > getBalance(user_, IERC20(vaultAddress_))) revert Nodes__WithdrawFromNestedStrategyInsufficientShares();

        _approve(vaultAddress_, address(selectNestedRoute), sharesAmount_);
        amountTokenDesired = selectNestedRoute.withdraw(user_, tokenOut_, vaultAddress_, sharesAmount_, provider_);

        decreaseBalance(user_, vaultAddress_, sharesAmount_);
        increaseBalance(user_, tokenOut_, amountTokenDesired);

        emit WithdrawFromNestedStrategy(tokenOut_, amountTokenDesired);
    }

    /**
    * @notice Function used to deposit tokens on a farm
    * @param user Address of the user.
    * @param lpToken_ Address of the LP Token.
    * @param tortleVault_ Address of the tortle vault where we are going to deposit.
    * @param tokens_ Addresses of tokens that are going to be deposited.
    * @param amount0_ Amount of token 0.
    * @param amount1_ Amount of token 1.
    * @param auxStack Contains information of the amounts that are going to be deposited.
    */
    function depositOnFarmTokens(
        address user,
        address lpToken_,
        address tortleVault_,
        address[] memory tokens_,
        uint256 amount0_,
        uint256 amount1_,
        uint256[] memory auxStack,
        uint8 provider_
    ) external nonReentrant onlyOwner returns (uint256[] memory result) {
        result = new uint256[](3);
        if (auxStack.length > 0) {
            amount0_ = auxStack[auxStack.length - 2];
            amount1_ = auxStack[auxStack.length - 1];
            result[0] = 2;
        }

        if (amount0_ > getBalance(user, IERC20(tokens_[0]))) revert Nodes__DepositOnFarmTokensInsufficientT0Funds();
        if (amount1_ > getBalance(user, IERC20(tokens_[1]))) revert Nodes__DepositOnFarmTokensInsufficientT1Funds();

        _approve(tokens_[0], address(selectLPRoute), amount0_);
        _approve(tokens_[1], address(selectLPRoute), amount1_);
        (uint256 amount0f_, uint256 amount1f_, uint256 lpBal_) = selectLPRoute.depositOnFarmTokens(lpToken_, tokens_, amount0_, amount1_, provider_);

        _approve(lpToken_, tortleVault_, lpBal_);
        uint256 ttAmount = ITortleVault(tortleVault_).deposit(user, lpBal_);

        decreaseBalance(user, tokens_[0], amount0f_);
        decreaseBalance(user, tokens_[1], amount1f_);
        increaseBalance(user, tortleVault_, ttAmount);

        result[1] = ttAmount;
        result[2] = lpBal_;

        emit DepositOnFarm(ttAmount, lpBal_);
    }

    /**
    * @notice Function used to withdraw tokens from a farm
    * @param user Address of the user.
    * @param lpToken_ Address of the LP Token.
    * @param tortleVault_ Address of the tortle vault where we are going to deposit.
    * @param tokens_ Addresses of tokens that are going to be deposited.
    * @param amountOutMin_ Minimum amount to be withdrawed.
    * @param amount_ Amount of tokens desired to withdraw.
    */
    function withdrawFromFarm(
        address user,
        address lpToken_,
        address tortleVault_,
        address[] memory tokens_,
        uint256 amountOutMin_,
        uint256 amount_, 
        uint8 provider_
    ) external nonReentrant onlyOwner returns (uint256 amountLp, uint256 rewardAmount, uint256 amountTokenDesired) {
        if (amount_ > getBalance(user, IERC20(tortleVault_))) revert Nodes__WithdrawFromFarmInsufficientFunds();

        (uint256 rewardAmount_, uint256 amountLp_) = ITortleVault(tortleVault_).withdraw(user, amount_);
        rewardAmount = rewardAmount_;
        amountLp = amountLp_;
        decreaseBalance(user, tortleVault_, amount_);

        _approve(lpToken_, address(selectLPRoute), amountLp_);
        amountTokenDesired = selectLPRoute.withdrawFromFarm(lpToken_, tokens_, amountOutMin_, amountLp_, provider_);

        increaseBalance(user, tokens_[2], amountTokenDesired);

        emit WithdrawFromFarm(tokens_[2], amountTokenDesired, rewardAmount);
    }

    /**
    * @notice Function that allows to liquidate all tokens in your account by swapping them to a specific token.
    * @param user_ Address of the user whose tokens are to be liquidated.
    * @param tokens_ Array of tokens input.
    * @param amount_ Array of amounts.
    * @param amountOutMin_ Minimum amount you wish to receive.
    * @param liquidateAmountWPercentage_ AddFunds amount with percentage.
    */
    function liquidate(
        address user_,
        IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        uint256 liquidateAmountWPercentage_,
        uint8 provider_,
        BatchSwapStep[] memory batchSwapStep_
    ) public onlyOwner returns (uint256 amountOut) {
        address tokenIn_ = address(tokens_[0]);
        address tokenOut_ = address(tokens_[tokens_.length - 1]);

        uint256 userBalance_ = getBalance(user_, IERC20(tokenIn_));
        if (userBalance_ < amount_) revert Nodes__InsufficientBalance();

        int256 profitAmount_ = int256(amount_) - int256(liquidateAmountWPercentage_);

        if (profitAmount_ > 0) {
            uint256 amountWithoutFees_ = _chargeFees(user_, tokens_, uint256(profitAmount_), amountOutMin_, PERFORMANCE_TOTAL_FEE, provider_, batchSwapStep_);
            uint256 amountFees_ = uint256(profitAmount_) - amountWithoutFees_;
            decreaseBalance(user_, tokenIn_, amountFees_);
            amount_ = (amount_ - uint256(profitAmount_)) + amountWithoutFees_;
        }

        amountOut = swapTokens(user_, provider_, tokens_, amount_, amountOutMin_, batchSwapStep_);

        decreaseBalance(user_, tokenOut_, amountOut);

        if(tokenOut_ == WFTM) {
            IWETH(WFTM).withdraw(amountOut);
            payable(user_).transfer(amountOut);
        } else {
            IERC20(tokenOut_).safeTransfer(user_, amountOut); 
        }

        emit Liquidate(tokenOut_, amountOut);
    }

    /**
    * @notice Function that allows to withdraw tokens to the user's wallet.
    * @param user_ Address of the user who wishes to remove the tokens.
    * @param tokens_ Token to be withdrawn.
    * @param amount_ Amount of tokens to be withdrawn.
    * @param addFundsAmountWPercentage_ AddFunds amount with percentage.
    */
    function sendToWallet(
        address user_,
        IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        uint256 addFundsAmountWPercentage_,
        uint8 provider_,
        BatchSwapStep[] memory batchSwapStep_
    ) public nonReentrant onlyOwner returns (uint256) {
        address tokenOut_ = address(tokens_[0]);
        uint256 _userBalance = getBalance(user_, IERC20(tokenOut_));
        if (_userBalance < amount_) revert Nodes__InsufficientBalance();

        decreaseBalance(user_, tokenOut_, amount_);

        int256 profitAmount_ = int256(amount_) - int256(addFundsAmountWPercentage_);

        if (profitAmount_ > 0) amount_ = (amount_ - uint256(profitAmount_)) + _chargeFees(user_, tokens_, uint256(profitAmount_), amountOutMin_, PERFORMANCE_TOTAL_FEE, provider_, batchSwapStep_);

        if (tokenOut_ == WFTM) {
            IWETH(WFTM).withdraw(amount_);
            payable(user_).transfer(amount_);
        } else IERC20(tokenOut_).safeTransfer(user_, amount_);

        emit SendToWallet(tokenOut_, amount_);
        return amount_;
    }

    /**
     * @notice Emergency function that allows to recover all tokens in the state they are in.
     * @param _tokens Array of the tokens to be withdrawn.
     * @param _amounts Array of the amounts to be withdrawn.
     */
    function recoverAll(IERC20[] memory _tokens, uint256[] memory _amounts) public nonReentrant {
        if (_tokens.length <= 0) revert Nodes__EmptyArray();
        if (_tokens.length != _amounts.length) revert Nodes__InvalidArrayLength();

        for (uint256 _i = 0; _i < _tokens.length; _i++) {
            IERC20 _tokenAddress = _tokens[_i];

            uint256 _userBalance = getBalance(msg.sender, _tokenAddress);
            if (_userBalance < _amounts[_i]) revert Nodes__InsufficientBalance();

            if(address(_tokenAddress) == WFTM) {
                IWETH(WFTM).withdraw(_amounts[_i]);
                payable(msg.sender).transfer(_amounts[_i]);
            } else _tokenAddress.safeTransfer(msg.sender, _amounts[_i]);
            
            decreaseBalance(msg.sender, address(_tokenAddress), _amounts[_i]);

            emit RecoverAll(address(_tokenAddress), _amounts[_i]);
        }
    }

    /**
     * @notice Approve of a token
     * @param token Address of the token wanted to be approved
     * @param spender Address that is wanted to be approved to spend the token
     * @param amount Amount of the token that is wanted to be approved.
     */
    function _approve(
        address token,
        address spender,
        uint256 amount
    ) internal {
        IERC20(token).safeApprove(spender, 0);
        IERC20(token).safeApprove(spender, amount);
    }

    /**
     * @notice Calculate the percentage of a number.
     * @param x Number.
     * @param y Percentage of number.
     * @param scale Division.
     */
    function mulScale(
        uint256 x,
        uint256 y,
        uint128 scale
    ) internal pure returns (uint256) {
        uint256 a = x / scale;
        uint256 b = x % scale;
        uint256 c = y / scale;
        uint256 d = y % scale;

        return a * c * scale + a * d + b * c + (b * d) / scale;
    }

    /**
    * @notice Function that allows you to see the balance you have in the contract of a specific token.
    * @param _user Address of the user who will deposit the tokens.
    * @param _token Contract of the token from which the balance is to be obtained.
    */
    function getBalance(address _user, IERC20 _token) public view returns (uint256) {
        return balance[_user].get(address(_token));
    }

    /**
     * @notice Increase balance of a token for a user
     * @param _user Address of the user that is wanted to increase its balance of a token
     * @param _token Address of the token that is wanted to be increased
     * @param _amount Amount of the token that is wanted to be increased
     */
    function increaseBalance(
        address _user,
        address _token,
        uint256 _amount
    ) private {
        uint256 _userBalance = getBalance(_user, IERC20(_token));
        _userBalance += _amount;
        balance[_user].set(address(_token), _userBalance);
    }

    /**
     * @notice Decrease balance of a token for a user
     * @param _user Address of the user that is wanted to decrease its balance of a token
     * @param _token Address of the token that is wanted to be decreased
     * @param _amount Amount of the token that is wanted to be decreased
     */
    function decreaseBalance(
        address _user,
        address _token,
        uint256 _amount
    ) private {
        uint256 _userBalance = getBalance(_user, IERC20(_token));
        if (_userBalance < _amount) revert Nodes__InsufficientBalance();

        _userBalance -= _amount;
        balance[_user].set(address(_token), _userBalance);
    }

    
    receive() external payable {}
}

