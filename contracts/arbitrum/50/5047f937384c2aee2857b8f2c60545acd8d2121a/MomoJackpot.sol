
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./SafeMath.sol";
import "./IERC20Metadata.sol";
import "./EnumerableSet.sol";

import "./IJackpotTool.sol";

contract MomoJackpot is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    struct Ticket {
        uint256 id;
        address user;
        uint probability;
    }

    struct InfoView {
        uint currentTicketCount;
        uint256 currentBonusPool;
        uint256 totalBonus;
        uint latestBonusTimestamp;
        uint256 minBonus;
        uint256 maxBonus;
    }

    event Winner(uint256 ticketId, address winner, uint256 bonus, uint timestamp);
    event NewTicket(uint256 ticketId, address user, uint256 probability, uint256 amount, uint256 amountUSD, uint timestamp);

    EnumerableSet.AddressSet private _callers;
    IERC20 public bonusToken;

    Ticket[] public tickets;
    uint256 public totalProbability;
    uint256 public minBonus;
    uint256 public maxBonus;
    uint[] public weights;
    uint256 public ticketId;
    uint256 public totalBonus;
    uint public latestBonusTimestamp;
    IJackpotTool public jackpotTool;
 
    constructor(IERC20 bonusToken_, IJackpotTool jackpotTool_, uint256 minBonus_, uint256 maxBonus_)  {
        bonusToken = bonusToken_;
        jackpotTool = jackpotTool_;
        minBonus = minBonus_;
        maxBonus = maxBonus_;
        weights = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000];
    }

    function lottery() public onlyCaller {

        uint256 bal = bonusToken.balanceOf(address(this));
        if(bal < minBonus) {
            return;
        }
        latestBonusTimestamp = block.timestamp;

        uint256 randomValue = uint256(keccak256(abi.encodePacked(block.timestamp, block.number))) % totalProbability;
        
        uint256 cumulativeProbability = 0;
        for (uint256 i = 0; i < tickets.length; i++) {
            cumulativeProbability += tickets[i].probability;
            if (randomValue < cumulativeProbability) {
                uint256 bonus = bal > maxBonus ? maxBonus:bal;
                bonusToken.transfer(tickets[i].user, bonus);
                totalBonus += bonus;
                emit Winner(tickets[i].id, tickets[i].user, bonus, block.timestamp);
                break;
            }
        }

        totalProbability = 0;
        delete tickets;
    }

    function _generateTicket(address user, uint256 amount) internal {
        ticketId++;
        (uint w, uint256 amountUSD) = getWeightWithTradeAmount(amount);
        tickets.push(Ticket({id:ticketId, user: user, probability: weights[w]}));
        totalProbability += weights[w];
        
        emit NewTicket(ticketId, user, weights[w], amount, amountUSD, block.timestamp);
    }

    function trade(address, uint256 amount) public onlyCaller {
        _generateTicket(tx.origin, amount);
    }

    function getWeightWithTradeAmount(uint256 amount) public view returns(uint tp, uint256 amountUSD) {
        uint256 value = jackpotTool.getCurrentUsdPrice(amount);
        return (getWeightWithTradeUsdAmount(value), value);
    }

    function getWeightWithTradeUsdAmount(uint256 amount) public pure returns(uint256) {
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

    function setWeights(uint[] memory vals) public onlyOwner {
        require(vals.length == weights.length, "bad length");
        weights = vals;
    }

    function setJackpotTool(IJackpotTool val) public onlyOwner {
        require(address(val) != address(0), "bad val");
        jackpotTool = val;
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
            currentTicketCount: tickets.length,
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
