// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./IERC20.sol";
import "./Ownable.sol";

interface IRouterV2 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function addLiquidityETH(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function factory() external view returns (address);

    function wETH() external view returns (address);
}

contract CustoPresale is Ownable {
    struct UserInfo {
        uint256 amount;
        bool claimed;
    }

    mapping(address => bool) public whitelist;
    mapping(address => bool) public ogWhitelist;
    mapping(address => UserInfo) public userInfo;

    uint256 public constant WL_MAX_AMOUNT = 0.25 ether;
    uint256 public constant OG_MAX_AMOUNT = 0.5 ether;
    uint256 public constant HARD_CAP = 75 ether;
    uint256 public constant RATE = 400000; // 1 ETH = 400,000 tokens

    uint256 public raised;
    uint256 public startTime;
    uint256 public duration;
    bool public isFinalized;
    bool public isOpenClaim;

    IERC20 public custo;
    IRouterV2 public router;

    event Claim(address indexed user, uint256 amount);
    event Buy(address indexed user, uint256 amount);
    event Finalize();
    event OpenClaim();

    constructor(address _custo, address _router) {
        custo = IERC20(_custo);
        router = IRouterV2(_router);
    }

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender] || ogWhitelist[msg.sender], 'Not whitelisted');
        _;
    }

    function buy() external payable onlyWhitelisted {
        require(block.timestamp >= startTime, 'Presale is not started');
        require(block.timestamp <= startTime + duration, 'Presale is ended');
        require(raised < HARD_CAP, 'Hard cap is reached');

        uint256 max = whitelist[msg.sender] ? WL_MAX_AMOUNT : OG_MAX_AMOUNT;
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = msg.value;

        if (amount + user.amount > max) {
            amount = max - user.amount;
        }

        if (raised + amount > HARD_CAP) {
            amount = HARD_CAP - raised;
        }

        require(amount > 0, 'Invalid amount');

        raised += amount;
        user.amount += amount;

        if (msg.value > amount) {
            payable(msg.sender).transfer(msg.value - amount);
        }

        emit Buy(msg.sender, amount);
    }

    function claim() external {
        require(isOpenClaim, 'Claim is not opened');
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, 'Invalid amount');
        require(!user.claimed, 'Already claimed');

        user.claimed = true;

        uint256 totalToken = user.amount * RATE;

        custo.transfer(msg.sender, totalToken);

        emit Claim(msg.sender, totalToken);
    }

    function finalize() external onlyOwner {
        require(!isFinalized, 'Already finalized');
        require(block.timestamp >= startTime + duration || raised == HARD_CAP, 'Presale not ended');

        uint256 totalToken = raised * RATE;

        custo.transferFrom(msg.sender, address(this), totalToken * 2);
        custo.approve(address(router), totalToken);

        router.addLiquidityETH{value : raised}(
            address(custo),
            false, // unstable,
            totalToken,
            0,
            0,
            msg.sender,
            block.timestamp
        );

        isFinalized = true;

        emit Finalize();
    }

    function addWL(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            if (!ogWhitelist[_addresses[i]] && !whitelist[_addresses[i]]) {
                whitelist[_addresses[i]] = true;
            }
        }
    }

    function addOGWL(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            if (!ogWhitelist[_addresses[i]] && !whitelist[_addresses[i]]) {
                ogWhitelist[_addresses[i]] = true;
            }
        }
    }

    function removeWL(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = false;
        }
    }

    function settings(uint256 _startTime, uint256 _duration) external onlyOwner {
        startTime = _startTime;
        duration = _duration;
    }

    function openClaim() external onlyOwner {
        require(isFinalized, 'Not finalized');
        isOpenClaim = true;
        emit OpenClaim();
    }

    function safu() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}
}

