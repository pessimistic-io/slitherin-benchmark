// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./ICamelotRouter.sol";
import "./ICamelotFactory.sol";
//import Address
import "./Address.sol";

interface IControl {
    function addLiquidity() external;
}


contract Control {
    IERC20 public weth;
    IERC20 public RIZZ;
    ICamelotRouter public router;
    address public owner;
    constructor(address weth_, address RIZZ_, address router_, address owner_) {
        weth = IERC20(weth_);
        RIZZ = IERC20(RIZZ_);
        router = ICamelotRouter(router_);
        weth.approve(address(router), type(uint).max);
        RIZZ.approve(address(router), type(uint).max);
        owner = owner_;


    }
    modifier onlyOwner{
        require(msg.sender == owner, "not owner");
        _;
    }

    function _addliquidity(uint amountA, uint amountB) internal {
        router.addLiquidityETH{value : amountA}(address(RIZZ), amountB, 0, 0, address(this), block.timestamp);
    }

    receive() external payable {
        //        assert(msg.sender == address(router));
        // only accept ETH via fallback from the WETH contract
    }

    function addLiquidity() external {
        require(msg.sender == address(RIZZ), 'wrong sender');
        uint tokenAmount = RIZZ.balanceOf(address(this));
        uint lastUAmount = address(this).balance;
        address[] memory path = new address[](2);
        path[0] = address(RIZZ);
        path[1] = address(weth);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount / 2, 0, path, address(this), address(0), block.timestamp);
        uint newUAmount = address(this).balance;
        _addliquidity(newUAmount - lastUAmount, tokenAmount / 2);
    }

    function safePull(address token, uint amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }

    function approve() external {
        weth.approve(address(router), type(uint).max);
        RIZZ.approve(address(router), type(uint).max);
    }
}

contract RIZZToken is ERC20, Ownable {
    mapping(address => bool) public pairs;
    address constant burnAddress = 0x000000000000000000000000000000000000dEaD;
    IERC20 public weth;
    uint public swapFee = 1;
    mapping(address => bool) public W;
    uint public swapLimit = 100 ether;
    IControl public control;
    mapping(address => bool) public outExcluded;
    address[] holders;
    ERC20 public lp;
    uint constant acc = 1e18;
    uint public lastIndex;
    mapping(address => uint) public holder_claimed;
    mapping(address => uint) public lp_claimed;
    mapping(address => bool) public isAdd;
    uint public shareAmount = 10;
    using Address for address;
    mapping(address => uint) lastClaimTime;

    struct Debt {
        uint lp_debt;
        uint holder_debt;
    }

    Debt public debt;
    constructor() ERC20("RIZZ", "RIZZ") {
        _mint(msg.sender, 2e15 ether);
        outExcluded[burnAddress] = true;
        outExcluded[address(0)] = true;
    }

    function checkHolders() public view returns (address[] memory){
        return holders;
    }

    function addPair(address pair, bool b) external onlyOwner {
        pairs[pair] = b;
    }

    function setW(address[] memory addrs, bool b) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
            W[addrs[i]] = b;
        }
    }

    function setSwapLimit(uint limit_) external onlyOwner {
        swapLimit = limit_;
    }

    function setOut(address[] memory addrs, bool b) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
            outExcluded[addrs[i]] = b;
        }
    }

    function setShareAmount(uint shareAmount_) external onlyOwner {
        shareAmount = shareAmount_;
    }

    function setAddress(address weth_, address router_) external onlyOwner {
        weth = IERC20(weth_);

        address pair = ICamelotFactory(ICamelotRouter(router_).factory()).getPair(address(this), address(weth));
        if (pair == address(0)) {
            pair = ICamelotFactory(ICamelotRouter(router_).factory()).createPair(address(this), address(weth));
        }
        pairs[pair] = true;
        address control_;
        lp = ERC20(pair);
        W[msg.sender] = true;
        bytes memory code = type(Control).creationCode;
        bytes memory bytecode = abi.encodePacked(code, abi.encode(weth, address(this), router_, msg.sender));
        //        bytes32 salt = keccak256(abi.encodePacked(address(this)));
        assembly {
            control_ := create2(0, add(bytecode, 32), mload(bytecode), 77)
        }
        control = IControl(control_);
        W[control_] = true;
        outExcluded[control_] = true;
        outExcluded[pair] = true;
    }

    function _processDebt(uint fee_) internal {
        uint lp_total = lp.totalSupply();
        if (lp_total > 0) {
            debt.lp_debt += fee_ * acc / lp_total;

        }
        debt.holder_debt += fee_ * acc / totalSupply();


    }

    function _processDividend() internal {
        uint temp = 0;
        uint timeNow = block.timestamp;
        uint _lastIndex = lastIndex;
        for (uint i = lastIndex; i < holders.length; i++) {
            if (temp >= shareAmount) {
                _lastIndex = i + 1;
                return;
            }
            if (i == holders.length - 1) {
                _lastIndex = 0;
            }
            address holder = holders[i];
            if (outExcluded[holder] || holder.isContract() || holder == address(this) || timeNow - lastClaimTime[holder] >= 600) {
                continue;
            }
            uint amount = balanceOf(holder) * debt.holder_debt / acc;
            uint lp_rew = lp.balanceOf(holder) * debt.lp_debt / acc;
            if (amount > 0 && balanceOf(address(this)) >= amount) {
                if (amount > holder_claimed[holder]) {
                    _transfer(address(this), holder, amount - holder_claimed[holder]);
                    holder_claimed[holder] = amount;
                }

            }
            if (lp_rew > 0 && balanceOf(address(this)) >= lp_rew) {
                if (lp_rew > lp_claimed[holder]) {
                    _transfer(address(this), holder, lp_rew - lp_claimed[holder]);
                    lp_claimed[holder] = lp_rew;
                }

            }
            lastClaimTime[holder] = timeNow;

            temp ++;
        }
        lastIndex = _lastIndex;
    }


    function _processTransfer(address from, address to, uint amount) internal {
        if (!isAdd[from] && !outExcluded[from] && !from.isContract()) {
            holders.push(from);
            isAdd[from] = true;
        }
        if (!isAdd[to] && !outExcluded[to] && !to.isContract()) {
            holders.push(to);
            isAdd[to] = true;
        }
        _processDividend();
        if (W[from] || W[to]) {
            holder_claimed[to] += holder_claimed[from] * amount / balanceOf(from);
            _transfer(from, to, amount);
            return;
        }

        if (pairs[from] || pairs[to]) {
            uint fee = amount * swapFee / 100;
            _transfer(from, to, amount - fee * 3);
            _transfer(from, address(control), fee);
            _transfer(from, address(this), fee * 2);
            _processDebt(fee);
            return;
        }

        if (balanceOf(address(control)) >= swapLimit) {
            control.addLiquidity();
        }
        holder_claimed[to] += holder_claimed[from] * amount / balanceOf(from);
        _transfer(from, to, amount);

    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _processTransfer(sender, recipient, amount);
        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    unchecked {
        _approve(sender, _msgSender(), currentAllowance - amount);
    }
        return true;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _processTransfer(msg.sender, recipient, amount);
        return true;
    }

    function safePull(address token, address wallet_, uint amount) external onlyOwner {
        IERC20(token).transfer(wallet_, amount);
    }

    function safePullETH(address wallet_, uint amount) external onlyOwner {
        payable(wallet_).transfer(amount);
    }

}

