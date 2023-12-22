pragma solidity ^0.6.12;

import "./FarmUtils.sol";

// T tokens (stake) are converted to 4 digits
// smaller amounts are dropped (min stake is 0.0001 arvault)
//
// or S tokens (arvault) is converted to 18 digits
// and then divided back to 9 digits on Withdraw
contract VaultFarmsZapperStaker {
    using SafeMath for uint256;

    uint256 public T = 0;
    uint256 public S = 0;
    mapping (address => uint256) public stake;
    mapping (address => uint256) public S0;
    mapping (address => uint256) public claimedReward;
    mapping (address => uint256) public pastReward;

    address public ROUTER;
    address public FARMS;
    address public ARVAULT;
    address public gov;

    uint public lastDistributedReward;

    event Yield(address indexed to, uint256 value);
    event Stake(address indexed to, uint256 value);

    // an example of accumulated arv converted to ray (18 decimals)
    // uint256 public bankRay = 200*(10**18);


    function Deposit(address _for, uint256 _amount) private {
        Distribute();
        uint prevStake = stake[_for];
        uint prevS = S0[_for];
        if (prevS == 0  || prevStake == 0) {
            S0[_for] = S;
            stake[_for] = stake[_for].add(_amount);
        } else {
            uint rewardForPeriod = _rewardForPeriod(_for);
            pastReward[_for] = pastReward[_for].add(rewardForPeriod);
            S0[_for] = S;
            stake[_for] = stake[_for].add(_amount);
        }
        T = T.add(_amount);
        emit Stake(_for, _amount);
    }

    // _r is the currently accrued arv reward
    function Distribute() public {
        uint cr = currentPoolRewardsRayAggr();
        uint _r = cr.sub(lastDistributedReward);
        if ((T != 0) && (_r > T)) {
            uint _rtRatio = _r.div(T);
            S = S.add(_rtRatio);
            lastDistributedReward = cr;
        }

    }

    //slippage protection
    mapping (address => uint256) public minArvForToken;

    //slippage protection
    function setMinArv(uint256 _amount, address _tok) public returns (uint256) {
        require(msg.sender == gov);
        minArvForToken[_tok] = _amount;
    }

    function setNextGov(address _nextGov) public returns (uint256) {
        require(msg.sender == gov);
        gov = _nextGov;
    }


    //slippage protection
    function minArv(uint256 _amount, address _tok) public view returns (uint256) {
        if (minArvForToken[_tok] != 0) {
            return minArvForToken[_tok].mul(_amount);
        } else {
            return 0;
        }
    }

    function swapTokensForArv(uint256 _tokenAmount, address _token) private  {
        // generate the uniswap pair path of token -> weth
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(ROUTER);
        address[] memory path;
        if (_token != _uniswapV2Router.WETH()) {
            path = new address[](3);
            path[0] = _token;
            path[1] = _uniswapV2Router.WETH();
            path[2] = ARVAULT;
        } else {
            path = new address[](2);
            path[0] = _token;
            path[1] = ARVAULT;
        }
        IERC20(_token).approve(ROUTER, _tokenAmount);
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        _tokenAmount,
        minArv(_tokenAmount, _token),
         path,
        address(this),
        block.timestamp.add(600));
    }

    function zapandstake(uint256 _amount, address _farm,
                         address _farmer, uint _minTok1, uint _minTok2) public {
        require(msg.sender == FARMS);
        address tok0 = IPair(_farm).token0();
        address tok1 = IPair(_farm).token1();
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(ROUTER);
        IERC20(_farm).approve(ROUTER , _amount);
        uint balBefore = IArvault(ARVAULT).balanceOfIdle(address(this));
         _uniswapV2Router.removeLiquidity(tok0,
                                          tok1,
                                          _amount,
                                          _minTok1,
                                          _minTok2,
                                          address(this),
                                          block.timestamp.add(600));
        if (tok0 != ARVAULT) {
            swapTokensForArv(IERC20(tok0).balanceOf(address(this)), tok0);
        }

        if (tok1 != ARVAULT) {
            swapTokensForArv(IERC20(tok1).balanceOf(address(this)), tok1);
        }

        uint balAfter = IArvault(ARVAULT).balanceOfIdle(address(this));
        uint arvTotal = balAfter.sub(balBefore);
        IArvault(ARVAULT).convertIdle(arvTotal);
        Deposit(_farmer, arvTotal);
    }

    function _rewardForPeriod(address _for) private view returns (uint256) {
        uint _deposited = stake[_for];
        uint _rewUser = S.sub(S0[_for]);
        uint _reward = _deposited.mul(_rewUser);
        return _reward.div(10**9);
    }

    function MyReward(address _for) public view returns (uint256) {
        uint aggReward = _rewardForPeriod(_for).add(pastReward[_for]);
        if (aggReward > claimedReward[_for]) {
            return aggReward.sub(claimedReward[_for]);
        } else {
            return 0;
        }
    }

    function Harvest() public  {
        uint _reward = MyReward(msg.sender);
        pastReward[msg.sender] = 0;
        claimedReward[msg.sender] = claimedReward[msg.sender].add(_reward);
        aggrWd = aggrWd.add(_reward);
        IArvault(ARVAULT).transfer(msg.sender, _reward);
        emit Yield(msg.sender,_reward);
    }

    function HarvestETH(uint256 _minETH) public  {
        uint _reward = MyReward(msg.sender);
        pastReward[msg.sender] = 0;
        claimedReward[msg.sender] = claimedReward[msg.sender].add(_reward);
        aggrWd = aggrWd.add(_reward);
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(ROUTER);
        address[] memory path = new address[](2);
        path[0] = ARVAULT;
        path[1] = _uniswapV2Router.WETH();
        IArvault(ARVAULT).approve(ROUTER, _reward);
        //  swap
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _reward,
            _minETH,
            path,
            msg.sender,
            block.timestamp.add(600)
        );
        emit Yield(msg.sender,_reward);
    }

    constructor (address _router, address _arvault, address _farms) public {
        ARVAULT = _arvault;
        ROUTER = _router;
        FARMS = _farms;
        gov = msg.sender;
    }

    function currentPoolRewardsRay() public view returns (uint256) {
        uint allTokens = IArvault(ARVAULT).balanceOf(address(this));
        return allTokens.mul(10**9);
    }

    function currentPoolRewardsRayAggr() public view returns (uint256) {
        uint allTokens = IArvault(ARVAULT).balanceOf(address(this));
        return allTokens.add(aggrWd).mul(10**9);
    }

    //accounting for all wds, wad
    uint public aggrWd;

     // recieve ETH from uniswapV2Router
    receive() external payable {}
}


interface IArvault {
    function balanceOfIdle(address _account) external view returns(uint256);
    function balanceOf(address account) external view returns (uint256);
    function convertIdle(uint256 _tconvertAmount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

