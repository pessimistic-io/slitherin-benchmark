// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./IERC20Metadata.sol";
import "./ISwapTools.sol";





contract Jackpot is OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    struct Tick {
        uint256 id;
        address user;
        uint probability;
    }

    struct InfoView {
        uint currentTicks;
        uint256 currentBonusPool;
        uint256 totalBonus;
        uint latestBonusTimestamp;
        uint256 minBonus;
        uint256 maxBonus;
    }

    event Winner(uint256 tickId, address winner, uint256 bonus, uint timestamp);
    event NewTick(uint256 tickId, address user, uint256 probability, uint256 amount, uint256 amountUSD, uint timestamp);

    EnumerableSet.AddressSet private _callers;
    IERC20 public bonusToken;

    Tick[] public ticks;
    uint256 public totalProbability;
    uint256 public minBonus;
    uint256 public maxBonus;
    uint[] public tickProbability;
    uint256 public tokenPrice;
    uint256 public tickId;
    uint256 public totalBonus;
    uint public latestBonusTimestamp;
    ISwapTools public swapTools;
    address public tradeToken;
    
    function initialize(IERC20 bonusToken_, address tradeToken_, ISwapTools swapTools_, uint256 minBonus_, uint256 maxBonus_) external initializer {
        __Ownable_init();
        bonusToken = bonusToken_;
        tradeToken = tradeToken_;
        swapTools = swapTools_;
        minBonus = minBonus_;
        maxBonus = maxBonus_;
        tickProbability = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000];
    }

    function lottery() public onlyCaller {

        uint256 bal = bonusToken.balanceOf(address(this));
        if(bal < minBonus) {
            return;
        }
        latestBonusTimestamp = block.timestamp;

        uint256 randomValue = uint256(keccak256(abi.encodePacked(block.timestamp, block.number))) % totalProbability;
        
        uint256 cumulativeProbability = 0;
        for (uint256 i = 0; i < ticks.length; i++) {
            cumulativeProbability += ticks[i].probability;
            if (randomValue < cumulativeProbability) {
                uint256 bonus = bal > maxBonus ? maxBonus:bal;
                bonusToken.transfer(ticks[i].user, bonus);
                totalBonus += bonus;
                emit Winner(ticks[i].id, ticks[i].user, bonus, block.timestamp);
                break;
            }
        }

        totalProbability = 0;
        delete ticks;
    }

    function _addTick(address user, uint256 amount) internal {
        tickId++;
        (uint tick, uint256 amountUSD) = getTickTypeWithTradeAmount(amount);
        ticks.push(Tick({id:tickId, user: user, probability: tickProbability[tick]}));
        totalProbability += tickProbability[tick];
        
        emit NewTick(tickId, user, tickProbability[tick], amount, amountUSD, block.timestamp);
    }

    function tradeEvent(address sender, uint256 amount) public onlyCaller {
        _addTick(sender, amount);

        tokenPrice = swapTools.getCurrentPrice(tradeToken);
    }

    function getTickTypeWithTradeAmount(uint256 amount) public view returns(uint tp, uint256 amountUSD) {
        uint8 decimals = IERC20Metadata(swapTools.anchorToken()).decimals();
        uint8 tradeTokenDecimals = IERC20Metadata(tradeToken).decimals();
        uint256 value = amount.mul(tokenPrice).div(10**tradeTokenDecimals).div(10**decimals);
        return (getTickTypeWithTradeUsdAmount(value), value);
    }

    function getTickTypeWithTradeUsdAmount(uint256 amount) public pure returns(uint256) {
        if (amount > 1000) {
            return 10;
        }
        return amount / 100;
    }

    function setMinBouns(uint256 val) public onlyOwner {
        require(val < maxBonus, "bad val");
        minBonus = val;
    }

    function setMaxBouns(uint256 val) public onlyOwner {
        require(val > minBonus, "bad val");
        maxBonus = val;
    }

    function setLatestBonusTimestamp(uint val) public onlyOwner {
        latestBonusTimestamp = val;
    }

    function setTickProbability(uint[] memory vals) public onlyOwner {
        require(vals.length == tickProbability.length, "bad length");
        tickProbability = vals;
    }

    function setTokenPrice(uint256 price) public onlyOwner {
        require(price > 0, "bad price");
        tokenPrice = price;
    }

    function setTradeToken(address val) public onlyOwner {
        require(val != address(0), "bad val");
        tradeToken = val;
    }

    function setSwapTools(ISwapTools val) public onlyOwner {
        require(address(val) != address(0), "bad val");
        swapTools = val;
    }

    function addCaller(address val) public onlyOwner() {
        require(val != address(0), "Jackpot: val is the zero address");
        _callers.add(val);
    }

    function delCaller(address caller) public onlyOwner returns (bool) {
        require(caller != address(0), "Jackpot: caller is the zero address");
        return _callers.remove(caller);
    }

    function getCallers() public view returns (address[] memory ret) {
        return _callers.values();
    }

    function getView() public view returns(InfoView memory) {
        return InfoView({
            currentTicks: ticks.length,
            currentBonusPool: bonusToken.balanceOf(address(this)),
            totalBonus: totalBonus,
            latestBonusTimestamp: latestBonusTimestamp,
            minBonus: minBonus,
            maxBonus: maxBonus
        });
    }

    modifier onlyCaller() {
        require(_callers.contains(_msgSender()), "onlyCaller");
        _;
    }

    receive() external payable {}
}
