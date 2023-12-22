// SPDX-License-Identifier: MIT
// Whispering secrets into the code...

// Listen, can you hear it?
// The whispers of the ghosts lurking in the code...

// Shhh... Keep it a secret
// But be careful, they are watching you...

// Don't mind me, I'm just the creepy whisper in the code...

// Creepy things happen in the dark corners of the code...

// Have you ever heard whispers in the dead of night?
// Well, now you have...

// The code is full of secrets, can you hear them whisper?

// https://t.me/whispersuser
// https://twitter.com/whispersuser

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract whispers is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable whisperedV2Router;
    address public immutable whisperedPair;
    address public constant graveyard = address(0x000000000000000000000000000000000000dEaD);

    bool private whispering;

    uint256 public maxHauntAmount;
    uint256 public bonesWhileWhispering;
    uint256 public maxGhostlyPresence;

    bool public fearsInEffect = true;
    bool public whisperingActive = false;
    bool public scareEnabled = false;

    mapping(address => uint256) private _lastEctoplasm; // Whispers move in the night, fleeting as the wind

    // alive
    mapping (address => uint256) private _firstWhisperTimestamp;

    bool public delayFear = true;

    uint256 public totalBuyScares;
    uint256 public preparingEctoplasmOperationFee;

    uint256 public totalSellScares;
    uint256 public completeEctoplasmOperationFee;

    /*** 666 ***/
    uint256 public scareDenominator;

    uint256 public tokensForEctoplasm; // must not...

    uint256 openedGraveyardAt;

    mapping (address => bool) private _noScares;
    mapping (address => bool) public _excludedMaxHauntAmount;

    // what?
    mapping (address => bool) public ghosts;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromWhispering(address indexed account, bool isExcluded);

    event ghostPeople(address indexed pair, bool indexed value);

    event WhisperAndHaunt(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    event AutoNukeLP();

    event ManualNukeLP();

    constructor() ERC20("whispers", "whispers") {

        IUniswapV2Router02 _whispaRouter = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // Arbitrum Sushiswap

        excludeFromHaunting(address(_whispaRouter), true);
        whisperedV2Router = _whispaRouter;

        whisperedPair = IUniswapV2Factory(_whispaRouter.factory()).createPair(address(this), _whispaRouter.WETH());
        excludeFromHaunting(address(whisperedPair), true);
        ghost(address(whisperedPair), true);

        uint256 _preparingEctoplasmOperationFee = 10;
        uint256 _completeEctoplasmOperationFee = 10;

        uint256 _scareDenominator = 100;

        uint256 totalOfWhispers = 666_666_666 * 1e18;

        maxHauntAmount = totalOfWhispers * 20 / 1000; // 2% maxTransactionAmountTxn
        maxGhostlyPresence = totalOfWhispers * 20 / 1000; // 2% maxWallet
        bonesWhileWhispering = totalOfWhispers * 3 / 10000; // 0.03% swap wallet

        scareDenominator = _scareDenominator;

        preparingEctoplasmOperationFee = _preparingEctoplasmOperationFee;
        totalBuyScares = preparingEctoplasmOperationFee;

        completeEctoplasmOperationFee = _completeEctoplasmOperationFee;
        totalSellScares = completeEctoplasmOperationFee;

        // exclude from paying fees or having max transaction amount
        excludeFromWhispering(owner(), true);
        excludeFromWhispering(address(this), true);
        excludeFromWhispering(address(0xdead), true);

        excludeFromHaunting(owner(), true);
        excludeFromHaunting(address(this), true);
        excludeFromHaunting(address(0xdead), true);

        _mint(msg.sender, totalOfWhispers);
    }

    receive() external payable {

    }

    // 1675536666
    function startEctoplasm() external onlyOwner {
        whisperingActive = true;
        scareEnabled = true;
        openedGraveyardAt = block.number;
    }

    // help
    function removeFear() external onlyOwner returns (bool){
        fearsInEffect = false;
        return true;
    }

    function excludeFromWhispering(address account, bool excluded) public onlyOwner {
        _noScares[account] = excluded;
        emit ExcludeFromWhispering(account, excluded);
    }

    function disableFear() external onlyOwner returns (bool){
        delayFear = false;
        return true;
    }

    function smashBonesWhileWhispering(uint256 newAmount) external onlyOwner returns (bool){
        require(newAmount >= totalSupply() * 1 / 100000);
        require(newAmount <= totalSupply() * 5 / 1000);
        bonesWhileWhispering = newAmount;
        return true;
    }

    function mustNotUse(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 5 / 1000)/1e18);
        maxHauntAmount = newNum * (10**18);
    }

    // yes...
    function scare(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 15 / 1000)/1e18);
        maxGhostlyPresence = newNum * (10**18);
    }

    function excludeFromHaunting(address updAds, bool isEx) public onlyOwner {
        _excludedMaxHauntAmount[updAds] = isEx;
    }

    function automateEctoplasm(address pair, bool value) public onlyOwner {
        require(pair != whisperedPair);

        ghost(pair, value);
    }

    function ghost(address pair, bool value) private {
        // https://upload.wikimedia.org/wikipedia/commons/f/f4/De_Alice%27s_Abenteuer_im_Wunderland_Carroll_pic_05.jpg
        ghosts[pair] = value;

        emit ghostPeople(pair, value);
    }

    function scream(uint256 _liquidityFee) external onlyOwner {
        preparingEctoplasmOperationFee = _liquidityFee;
        totalBuyScares = preparingEctoplasmOperationFee;
        require(totalBuyScares.div(scareDenominator) <= 10);
    }

    function shout(uint256 _liquidityFee) external onlyOwner {
        completeEctoplasmOperationFee = _liquidityFee;
        totalSellScares = completeEctoplasmOperationFee;
        require(totalSellScares.div(scareDenominator) <= 10);
    }

    function areYouScared(address account) public view returns(bool) {
        return _noScares[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0));
        require(to != address(0));
        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if(fearsInEffect){
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !whispering
            ){
                if(!whisperingActive){
                    require(_noScares[from] || _noScares[to], "help");
                }

                // ectoplasm time?
                if (delayFear) {
                    if (to != owner() && to != address(whisperedV2Router) && to != address(whisperedPair)){
                        require(_lastEctoplasm[tx.origin] < block.number, "only 1 shout is per life");
                        _lastEctoplasm[tx.origin] = block.number;
                    }
                }

                // when to shout
                if (ghosts[from] && !_excludedMaxHauntAmount[to]) {
                    require(amount <= maxHauntAmount, "please");
                    require(amount + balanceOf(to) <= maxGhostlyPresence, "i cant");
                }

                // ...
                else if (ghosts[to] && !_excludedMaxHauntAmount[from]) {
                    require(amount <= maxHauntAmount, "don't hurt me...");
                }
                else if(!_excludedMaxHauntAmount[to]){
                    require(amount + balanceOf(to) <= maxGhostlyPresence, "----");
                }
            }
        }

        uint256 bones = balanceOf(address(this));

        bool canHurt = bones >= bonesWhileWhispering;

        if(
            canHurt &&
            scareEnabled &&
            !whispering &&
            !ghosts[from] &&
            !_noScares[from] &&
            !_noScares[to]
        ) {
            whispering = true;

            hurt();

            whispering = false;
        }

        bool takeBlood = !whispering;

        if(_noScares[from] || _noScares[to]) {
            takeBlood = false;
        }

        uint256 litresOfBlood = 0;
        if(takeBlood){
            if (ghosts[to] && totalSellScares > 0){
                litresOfBlood = amount.mul(totalSellScares).div(scareDenominator);
                tokensForEctoplasm += litresOfBlood * completeEctoplasmOperationFee / totalSellScares;
            }
            else if(ghosts[from] && totalBuyScares > 0) {
                litresOfBlood = amount.mul(totalBuyScares).div(scareDenominator);
                tokensForEctoplasm += litresOfBlood * preparingEctoplasmOperationFee / totalBuyScares;
            }

            if(litresOfBlood > 0){
                super._transfer(from, address(this), litresOfBlood);
            }

            amount -= litresOfBlood;
        }

        super._transfer(from, to, amount);
    }

    function toothForBlood(uint256 teeths) private {
        address[] memory darkness = new address[](2);
        darkness[0] = address(this);
        darkness[1] = whisperedV2Router.WETH();

        _approve(address(this), address(whisperedV2Router), teeths);

        // make the swap
        whisperedV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            teeths,
            0,
            darkness,
            address(this),
            block.timestamp
        );
    }

    function pushCoffin(uint256 coffins, uint256 teeths) private {
        _approve(address(this), address(whisperedV2Router), coffins);

        whisperedV2Router.addLiquidityETH{value: teeths}(
            address(this),
            coffins,
            0,
            0,
            graveyard,
            block.timestamp
        );
    }

    function hurt() private {
        uint256 whisperings = balanceOf(address(this));
        uint256 ectoplasms = tokensForEctoplasm;
        bool success;

        if(whisperings == 0 || ectoplasms == 0) {return;}

        if(whisperings > bonesWhileWhispering * 20){
            whisperings = bonesWhileWhispering * 20;
        }

        uint256 black = whisperings * tokensForEctoplasm / ectoplasms / 2;
        uint256 light = whisperings.sub(black);

        uint256 coffins = address(this).balance;

        toothForBlood(light);

        uint256 hisses = address(this).balance.sub(coffins);

        tokensForEctoplasm = 0;

        if(black > 0 && hisses > 0){
            pushCoffin(black, hisses);
            emit WhisperAndHaunt(light, hisses, tokensForEctoplasm);
        }
    }
}

