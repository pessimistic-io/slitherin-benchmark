// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

interface ILionDEXRouter {
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

contract LionDEXBlindBox is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public lionToken;
    IERC20 public esLionToken;
    ILionDEXRouter public lionDexSwapRouter;
    address public weth;
    address public treasuryAddress;

    uint public counters;
    uint public boxUnitPriceLion;

    uint[] public weights;
    uint[] public lionRates;
    uint[] public esLionRates;
    uint[] public stockIncrs;
    uint public circle;
    uint public totalWeight;
    uint public lastResult;
    uint public  phaseBoxNumber;

    event OpenBox(address sender, uint counters, uint prizeId, uint lionPrize, uint esLionPrize);
    event Buy(address sender, uint buyNumber, uint payETHAmount, uint lionAmount, uint treasuryAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(){
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    function initialize(
        address _lionToken,
        address _esLionToken,
        address _lionDexSwapRouter,
        address _treasuryAddress,
        address _weth
    ) initializer public {
        __Ownable_init();
        __Pausable_init();

        lionToken = IERC20(_lionToken);
        esLionToken = IERC20(_esLionToken);
        lionDexSwapRouter = ILionDEXRouter(_lionDexSwapRouter);
        weth = _weth;
        treasuryAddress = _treasuryAddress;
        boxUnitPriceLion = 5000e18;

        phaseBoxNumber = 800;
        circle = 100;
        totalWeight = 10000;
        weights = new uint[](4);
        weights[0] = 2500;
        weights[1] = 2500;
        weights[2] = 2500;
        weights[3] = 2500;

        lionRates = new uint[](4);
        lionRates[0] = 70;
        lionRates[1] = 80;
        lionRates[2] = 90;
        lionRates[3] = 100;

        esLionRates = new uint[](4);
        esLionRates[0] = 70;
        esLionRates[1] = 50;
        esLionRates[2] = 30;
        esLionRates[3] = 10;

        stockIncrs = new uint[](4);
    }

    function setWETH(address _weth) external onlyOwner {
        weth = _weth;
    }

    function setLionToken(address _lionToken) external onlyOwner {
        lionToken = IERC20(_lionToken);
    }

    function setEsLionToken(address _esLionToken) external onlyOwner {
        esLionToken = IERC20(_esLionToken);
    }

    function setLionDexSwapRouter(address _lionDexSwapRouter) external onlyOwner {
        lionDexSwapRouter = ILionDEXRouter(_lionDexSwapRouter);
    }

    function setBoxUnitPriceLion(uint _boxUnitPriceLion) external onlyOwner {
        boxUnitPriceLion = _boxUnitPriceLion;
    }

    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    function setPhaseBoxNumber(uint256 _boxNumber) external onlyOwner{
        phaseBoxNumber = _boxNumber;
    }
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getBoxUnitPriceETH() public view returns (uint priceETH) {
        address[] memory paths = new address[](2);
        paths[0] = address(lionToken);
        paths[1] = weth;
        uint[] memory amounts = lionDexSwapRouter.getAmountsOut(boxUnitPriceLion, paths);
        priceETH = amounts[1];
    }
    function getPhaseLeftBoxNumber() external view returns(uint256){
         return phaseBoxNumber-counters;
    }
    function buy(uint buyNumber) payable whenNotPaused external {
        require(buyNumber > 0 && buyNumber <= 10, 'invalid number');
        require(counters+buyNumber <= phaseBoxNumber,'phase Box sold out');
        uint payETHAmount = getBoxUnitPriceETH() * buyNumber;
        uint sendValue = msg.value;
        require(sendValue >= payETHAmount, 'send ETH insufficient');
        if (sendValue > payETHAmount) {
            uint refund = sendValue- payETHAmount;
            payable(msg.sender).transfer(refund);
        }
        uint lionAmount = _swapLion(payETHAmount);
        uint avgLionAmount = lionAmount / buyNumber;
        uint lionPrizeAmount;
        uint esLionPrizeAmount;
        bytes32 bh1 = blockhash(block.number - 1);
        bytes32 bh2 = blockhash(block.number - 2);
        uint _lastSeed = lastResult;
        for (uint i = 0; i < buyNumber; ++i) {
            uint256 seed = uint256(keccak256(abi.encode(_lastSeed,bh2,block.gaslimit, block.coinbase, bh1, (i+1)*3279)));
            uint prizeId = _randomWeight(seed,totalWeight);

            if (prizeId > 0) {
                uint rounds = counters / circle + 1;
                uint totalStock = rounds * weights[prizeId] / 100;
                if (stockIncrs[prizeId] >= totalStock) {
                    prizeId = 0;
                }
            }
            stockIncrs[prizeId] = stockIncrs[prizeId] + 1;

            uint lionPrize = avgLionAmount * lionRates[prizeId] / 100;
            lionPrizeAmount += lionPrize;

            uint esLionPrize = avgLionAmount * esLionRates[prizeId] / 100;
            esLionPrizeAmount += esLionPrize;

            counters += 1;
            _lastSeed = seed;
            emit OpenBox(msg.sender, counters, prizeId, lionPrize, esLionPrize);
        }
        lastResult = _lastSeed;

        lionToken.transfer(msg.sender, lionPrizeAmount);
        esLionToken.transfer(msg.sender, esLionPrizeAmount);
        uint lionBalance = lionToken.balanceOf(address(this));
        if (lionBalance > 0) {
            lionToken.transfer(treasuryAddress, lionBalance);
        }
        emit Buy(msg.sender, buyNumber, payETHAmount, lionAmount, lionBalance);
    }

    function _randomUint(uint256 seed, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min >= max) {
            return min;
        }
        return seed % (max - min + 1) + min;
    }

    function _randomWeight(uint seed, uint256 total) view internal returns (uint256) {
        uint256 number = _randomUint(seed, 1, total);
        for (uint256 i = weights.length - 1; i != 0; --i) {
            if (number <= weights[i]) {
                return i;
            }
            number -= weights[i];
        }
        return 0;
    }


    function _swapLion(uint amountETH) internal returns (uint lionAmount) {
        address[] memory paths = new address[](2);
        paths[0] = weth;
        paths[1] = address(lionToken);
        lionDexSwapRouter.swapExactETHForTokens{value : amountETH}(
            0, paths, address(this), block.timestamp);
        lionAmount = lionToken.balanceOf(address(this));
    }

    function rescueToken(address _token,uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(
            msg.sender,
         _amount);
    }

    receive() external payable {}
}

