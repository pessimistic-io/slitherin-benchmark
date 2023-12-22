// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IERC20.sol";
import "./Nodes.sol";
import "./StringUtils.sol";
import "./IBeets.sol";

contract Batch {
    address public masterOwner;
    mapping(address => uint8) public owners;
    Nodes public nodes;
    uint8 public constant TOTAL_FEE = 150; //1.50%
    uint256[] public auxStack;
    BatchSwapStep[] private batchSwapStep;

    struct Function {
        string recipeId;
        string id;
        string functionName;
        address user;
        bytes arguments;
        bool hasNext;
    }

    struct BatchSwapStruct {
        bytes32[] poolId;
        uint256[] assetInIndex;
        uint256[] assetOutIndex;
        uint256[] amount;
    }

    struct SplitStruct {
        IAsset[] firstTokens;
        IAsset[] secondTokens;
        uint256 amount;
        uint256[] percentageAndAmountsOutMin;
        uint8[] providers;
        BatchSwapStruct batchSwapStepFirstToken;
        BatchSwapStruct batchSwapStepSecondToken;
        string firstHasNext;
        string secondHasNext;
    }

    event AddFundsForTokens(string indexed recipeId, string indexed id, address tokenInput, uint256 amount);
    event AddFundsForFTM(string indexed recipeId, string indexed id, uint256 amount);
    event Split(string indexed recipeId, string indexed id, address tokenInput, uint256 amountIn, address tokenOutput1, uint256 amountOutToken1, address tokenOutput2, uint256 amountOutToken2);
    event SwapTokens(string indexed recipeId, string indexed id, address tokenInput, uint256 amountIn, address tokenOutput, uint256 amountOut);
    event Liquidate(string indexed recipeId, string indexed id, address tokenInput, uint256 amountIn, address tokenOutput, uint256 amountOut);
    event SendToWallet(string indexed recipeId, string indexed id, address tokenOutput, uint256 amountOut);
    event lpDeposited(string indexed recipeId, string indexed id, address lpToken, uint256 amount);
    event ttDeposited(string indexed recipeId, string indexed id, address ttVault, uint256 lpAmount, uint256 amount);
    event DepositOnNestedStrategy(string indexed recipeId, string indexed id, address vaultAddress, uint256 amount);
    event WithdrawFromNestedStrategy(string indexed recipeId, string indexed id, address vaultAddress, uint256 amountShares, address tokenDesired, uint256 amountDesired);
    event lpWithdrawed(string indexed recipeId, string indexed id, address lpToken, uint256 amountLp, address tokenDesired, uint256 amountTokenDesired);
    event ttWithdrawed(string indexed recipeId, string indexed id, uint256 lpAmount, address ttVault, uint256 amountTt, address tokenDesired, uint256 amountTokenDesired, uint256 rewardAmount);

    constructor(address masterOwner_) {
        masterOwner = masterOwner_;
    }

    modifier onlyMasterOwner() {
        require(msg.sender == masterOwner, 'You must be the owner.');
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == masterOwner || owners[msg.sender] == 1, 'You must be the owner.');
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), 'This function is internal.');
        _;
    }

    function setNodeContract(Nodes _nodes) public onlyMasterOwner {
        nodes = _nodes;
    }

    function addOwners(address[] memory owners_) public onlyMasterOwner {
        require(owners_.length > 0, 'The array must have at least one address.');

        for (uint8 i = 0; i < owners_.length; i++) {
            require(owners_[i] != address(0), 'Invalid address.');

            if (owners[owners_[i]] == 0) owners[owners_[i]] = 1;
        }
    }

    function removeOwners(address[] memory owners_) public onlyMasterOwner {
        require(owners_.length > 0, 'The array must have at least one address.');

        for (uint8 i = 0; i < owners_.length; i++) {
            if (owners[owners_[i]] == 1) owners[owners_[i]] = 0;
        }
    }

    function batchFunctions(Function[] memory _functions) public onlyOwner {
        for (uint256 i = 0; i < _functions.length; i++) {
            (bool success, ) = address(this).call(abi.encodeWithSignature(_functions[i].functionName, _functions[i]));
            if (!success) revert();
        }
        if (auxStack.length > 0) deleteAuxStack();
    }

    function deleteAuxStack() private {
        uint256 arrayLength_ = auxStack.length;
        for (uint8 i; i < arrayLength_; i++) {
            auxStack.pop();
        }
    }

    function deleteBatchSwapStep() private {
        uint256 arrayLength_ = batchSwapStep.length;
        for (uint8 i; i < arrayLength_; i++) {
            batchSwapStep.pop();
        }
    }

    function createBatchSwapObject(BatchSwapStruct memory batchSwapStruct_) private returns(BatchSwapStep[] memory newBatchSwapStep) {
        for(uint16 x; x < batchSwapStruct_.poolId.length; x++) {
            BatchSwapStep memory batchSwapStep_;
            batchSwapStep_.poolId = batchSwapStruct_.poolId[x];
            batchSwapStep_.assetInIndex = batchSwapStruct_.assetInIndex[x];
            batchSwapStep_.assetOutIndex = batchSwapStruct_.assetOutIndex[x];
            batchSwapStep_.amount = batchSwapStruct_.amount[x];
            batchSwapStep_.userData = bytes("0x");
            batchSwapStep.push(batchSwapStep_);
        }
        newBatchSwapStep = batchSwapStep;
        deleteBatchSwapStep();
    }

    function addFundsForTokens(Function memory args) public onlySelf {
        (IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        uint8 provider_,
        BatchSwapStruct memory batchSwapStruct_) = abi.decode(args.arguments, (IAsset[], uint256, uint256, uint8, BatchSwapStruct));

        BatchSwapStep[] memory batchSwapStep_;
        if(provider_ == 1) {
            batchSwapStep_ = createBatchSwapObject(batchSwapStruct_);
        }

        uint256 amount = nodes.addFundsForTokens(args.user, tokens_, amount_, amountOutMin_, provider_, batchSwapStep_);
        
        if (args.hasNext) {
            auxStack.push(amount);
        }

        emit AddFundsForTokens(args.recipeId, args.id, address(tokens_[0]), amount);
    }

    function addFundsForFTM(Function memory args) public onlySelf {
        uint256 amount_ = abi.decode(args.arguments, (uint256));
        uint256 _fee = ((amount_ * TOTAL_FEE) / 10000);
        amount_ -= _fee;
        if (args.hasNext) {
            auxStack.push(amount_);
        }

        emit AddFundsForFTM(args.recipeId, args.id, amount_);
    }

    function swapTokens(Function memory args) public onlySelf {
        (IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        BatchSwapStruct memory batchSwapStruct_,
        uint8 provider_) = abi.decode(args.arguments, (IAsset[], uint256, uint256, BatchSwapStruct, uint8));
        
        if (auxStack.length > 0) {
            amount_ = auxStack[auxStack.length - 1];
            auxStack.pop();
        }

        BatchSwapStep[] memory batchSwapStep_;
        if(provider_ == 1) {
            batchSwapStep_ = createBatchSwapObject(batchSwapStruct_);
        }

        uint256 amountOut = nodes.swapTokens(args.user, provider_, tokens_, amount_, amountOutMin_, batchSwapStep_);
        if (args.hasNext) {
            auxStack.push(amountOut);
        }

        emit SwapTokens(args.recipeId, args.id, address(tokens_[0]), amount_, address(tokens_[tokens_.length - 1]), amountOut);
    }

    function split(Function memory args) public onlySelf {
        (SplitStruct memory splitStruct_) = abi.decode(args.arguments, (SplitStruct));

        if (auxStack.length > 0) {
            splitStruct_.amount = auxStack[auxStack.length - 1];
            auxStack.pop();
        }

        BatchSwapStep[] memory batchSwapStepFirstToken_;
        if(splitStruct_.providers[0] == 1) {
            batchSwapStepFirstToken_ = createBatchSwapObject(splitStruct_.batchSwapStepFirstToken);
        }

        BatchSwapStep[] memory batchSwapStepSecondToken_;
        if(splitStruct_.providers[1] == 1) {
            batchSwapStepSecondToken_ = createBatchSwapObject(splitStruct_.batchSwapStepSecondToken);
        }

        bytes memory data = abi.encode(args.user, splitStruct_.firstTokens, splitStruct_.secondTokens, splitStruct_.amount, splitStruct_.percentageAndAmountsOutMin, splitStruct_.providers);
        uint256[] memory amountOutTokens = nodes.split(data, batchSwapStepFirstToken_, batchSwapStepSecondToken_);

        if (StringUtils.equal(splitStruct_.firstHasNext, 'y')) {
            auxStack.push(amountOutTokens[0]);
        }
        if (StringUtils.equal(splitStruct_.secondHasNext, 'y')) {
           auxStack.push(amountOutTokens[1]);
        }

        emit Split(args.recipeId, args.id, address(splitStruct_.firstTokens[0]), splitStruct_.amount, address(splitStruct_.firstTokens[splitStruct_.firstTokens.length - 1]), amountOutTokens[0], address(splitStruct_.secondTokens[splitStruct_.secondTokens.length - 1]), amountOutTokens[1]);
    }

    function depositOnLp(Function memory args) public onlySelf {
        (bytes32 poolId_,
        address lpToken_,
        address[] memory tokens_,
        uint256[] memory amounts_,
        uint256 amountOutMin0_,
        uint256 amountOutMin1_,
        uint8 provider_) = abi.decode(args.arguments, (bytes32, address, address[], uint256[], uint256, uint256, uint8));

        if(auxStack.length > 0) {
            if(provider_ == 0) {
                amounts_[0] = auxStack[auxStack.length - 2];
                amounts_[1] = auxStack[auxStack.length - 1];
                auxStack.pop();
                auxStack.pop();
            } else {
                amounts_[0] = auxStack[auxStack.length - 1];
                auxStack.pop();
            }
        }

        uint256 lpRes = nodes.depositOnLp(
            args.user,
            poolId_,
            lpToken_,
            provider_,
            tokens_,
            amounts_,
            amountOutMin0_,
            amountOutMin1_
        );

        if (args.hasNext) {
            auxStack.push(lpRes);
        }

        emit lpDeposited(args.recipeId, args.id, lpToken_, lpRes);
    }

    function withdrawFromLp(Function memory args) public onlySelf {
        (bytes32 poolId_,
        address lpToken_,
        address[] memory tokens_,
        uint256[] memory amountsOutMin_,
        uint256 amount_,
        uint8 provider_) = abi.decode(args.arguments, (bytes32, address, address[], uint256[], uint256, uint8));

        if (auxStack.length > 0) {
            amount_ = auxStack[auxStack.length - 1];
            auxStack.pop();
        }

        uint256 amountTokenDesired = nodes.withdrawFromLp(args.user, poolId_, lpToken_, provider_, tokens_, amountsOutMin_, amount_);
        
        if (args.hasNext) {
            auxStack.push(amountTokenDesired);
        }

        address tokenOut_;
        if(provider_ == 0) {
            tokenOut_ = tokens_[2];
        } else {
            tokenOut_ = tokens_[0];
        }

        emit lpWithdrawed(
            args.recipeId,
            args.id,
            lpToken_,
            amount_,
            tokenOut_,
            amountTokenDesired
        );
    }

    function depositOnNestedStrategy(Function memory args) public onlySelf {
        (address token_,
        address vaultAddress_,
        uint256 amount_,
        uint8 provider_) = abi.decode(args.arguments, (address, address, uint256, uint8));

        if (auxStack.length > 0) {
            amount_ = auxStack[auxStack.length - 1];
            auxStack.pop();
        }

        uint256 sharesAmount_ = nodes.depositOnNestedStrategy(args.user, token_, vaultAddress_, amount_, provider_);

        if (args.hasNext) {
            auxStack.push(sharesAmount_);
        }

        emit DepositOnNestedStrategy(args.recipeId, args.id, vaultAddress_, sharesAmount_);
    }

    function withdrawFromNestedStrategy(Function memory args) public onlySelf {
        (address tokenOut_,
        address vaultAddress_,
        uint256 amount_,
        uint8 provider_) = abi.decode(args.arguments, (address, address, uint256, uint8));

        if (auxStack.length > 0) {
            amount_ = auxStack[auxStack.length - 1];
            auxStack.pop();
        }

        uint256 amountTokenDesired_ = nodes.withdrawFromNestedStrategy(args.user, tokenOut_, vaultAddress_, amount_, provider_);

        if (args.hasNext) {
            auxStack.push(amountTokenDesired_);
        }

        emit WithdrawFromNestedStrategy(args.recipeId, args.id, vaultAddress_, amount_, tokenOut_, amountTokenDesired_);
    }

    function depositOnFarm(Function memory args) public onlySelf {
        (address lpToken_,
        address tortleVault_,
        address[] memory tokens_,
        uint256 amount0_,
        uint256 amount1_,
        uint8 provider_) = abi.decode(args.arguments, (address, address, address[], uint256, uint256, uint8));

        uint256[] memory result_ = nodes.depositOnFarmTokens(args.user, lpToken_, tortleVault_, tokens_, amount0_, amount1_, auxStack, provider_);
        while (result_[0] != 0) {
            auxStack.pop();
            result_[0]--;
        }

        emit ttDeposited(args.recipeId, args.id, tortleVault_, result_[2], result_[1]); // ttVault address and ttAmount
        if (args.hasNext) {
            auxStack.push(result_[1]);
        }
    }

    function withdrawFromFarm(Function memory args) public onlySelf {
        (address lpToken_,
        address tortleVault_,
        address[] memory tokens_,
        uint256 amountOutMin_,
        uint256 amount_,
        uint8 provider_) = abi.decode(args.arguments, (address, address, address[], uint256, uint256, uint8));

        if (auxStack.length > 0) {
            amount_ = auxStack[auxStack.length - 1];
            auxStack.pop();
        }

        (uint256 amountLp, uint256 rewardAmount, uint256 amountTokenDesired) = nodes.withdrawFromFarm(args.user, lpToken_, tortleVault_, tokens_, amountOutMin_, amount_, provider_);
        
        if (args.hasNext) {
            auxStack.push(amountTokenDesired);
        }

        emit ttWithdrawed(
            args.recipeId,
            args.id,
            amountLp,
            tortleVault_,
            amount_,
            tokens_[2],
            amountTokenDesired,
            rewardAmount
        );
    }

    function sendToWallet(Function memory args) public onlySelf {
        (IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        uint256 addFundsAmountWPercentage_,
        uint8 provider_,
        BatchSwapStruct memory batchSwapStruct_) = abi.decode(args.arguments, (IAsset[], uint256, uint256, uint256, uint8, BatchSwapStruct));

        if (auxStack.length > 0) {
            amount_ = auxStack[auxStack.length - 1];
            auxStack.pop();
        }

        BatchSwapStep[] memory batchSwapStep_;
        if(provider_ == 1) {
            batchSwapStep_ = createBatchSwapObject(batchSwapStruct_);
        }

        uint256 amount = nodes.sendToWallet(args.user, tokens_, amount_, amountOutMin_, addFundsAmountWPercentage_, provider_, batchSwapStep_);

        emit SendToWallet(args.recipeId, args.id, address(tokens_[0]), amount);
    }

    function liquidate(Function memory args) public onlySelf {
        (IAsset[] memory tokens_,
        uint256 amount_,
        uint256 amountOutMin_,
        uint256 liquidateAmountWPercentage_,
        uint8 provider_,
        BatchSwapStruct memory batchSwapStruct_) = abi.decode(args.arguments, (IAsset[], uint256, uint256, uint256, uint8, BatchSwapStruct));

        if(auxStack.length > 0) {
            amount_ = auxStack[auxStack.length - 1];
            auxStack.pop();
        }
        
        BatchSwapStep[] memory batchSwapStep_;
        if(provider_ == 1) {
            batchSwapStep_ = createBatchSwapObject(batchSwapStruct_);
        }

        uint256 amountOut = nodes.liquidate(args.user, tokens_, amount_, amountOutMin_, liquidateAmountWPercentage_, provider_, batchSwapStep_);

        emit Liquidate(args.recipeId, args.id, address(tokens_[0]), amount_, address(tokens_[tokens_.length - 1]), amountOut);
    }

    receive() external payable {}
}

