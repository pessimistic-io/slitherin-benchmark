/*





*/ // SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "./ERC20.sol";

interface IFrenRewarder {
    function fill(uint256 day, uint256 amount) external;
    function setBased(address) external;
}

contract Skadoodle is ERC20 {
    address public admin;

    uint256 public constant maxSupply = 108_000_000e18;
    uint256 public maxTradeAmount = 100e18;
    address public frenRewarder;
    uint256 public startTimestamp;
    mapping(uint256 => bool) public isRewardMinted;
    mapping(address => bool) public isAuth;

    constructor(address admin_) ERC20("SKIDADDLE", "SKADOODLE") {
        admin = admin_;

        _mint(admin, 72_000_000e18);
    }

    modifier onlyAuth() {
        require(msg.sender == admin || isAuth[msg.sender], "Caller is not the authorized");
        _;
    }

    function setIsAuth(address fren, bool isAuthorized) external onlyAuth {
        isAuth[fren] = isAuthorized;
    }

    function initialize(address frenRewarder_, uint256 startTimestamp_) external {
        require(msg.sender == admin, "ONLY ADMIN");
        require(frenRewarder_ != address(0) && startTimestamp_ > block.timestamp, "BAD PARAMS");

        frenRewarder = frenRewarder_;
        startTimestamp = startTimestamp_;

        _approve(address(this), frenRewarder, maxSupply - totalSupply());

        admin = address(0);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(amount <= maxTradeAmount, "Exceeds max trade amount");
        return super.transfer(recipient, amount);
    }

    function getFrenRewardAmount(uint256 day) public view returns (uint256) {
        if (day < 21) return 96396396396396300000000;
        if (day < 21 * 2) return 63963963963963000000000;
        if (day < 21 * 3) return 39639639639630000000000;
        if (day < 21 * 4) return 9639639639639630000000;
        if (maxSupply - totalSupply() < 96396396396396300000000) return maxSupply - totalSupply();
        return 0;
    }

    function increaseMaxTradeAmount(uint256 newMaxTradeAmount) external {
        require(msg.sender == admin, "ONLY ADMIN");
        require(newMaxTradeAmount >= maxTradeAmount, "Cannot decrease max trade amount");

        maxTradeAmount = newMaxTradeAmount;
    }

    function fillFrenRewarder(uint256 day) external {
        require(block.timestamp >= startTimestamp, "NOT STARTED");
        require(startTimestamp + day * 1 days < block.timestamp, "NOT REACHED DAY");

        if (!isRewardMinted[day]) {
            isRewardMinted[day] = true;

            uint256 amount = getFrenRewardAmount(day);
            if (amount > 0) {
                _mint(admin, amount);
            }
        }
    }
}

