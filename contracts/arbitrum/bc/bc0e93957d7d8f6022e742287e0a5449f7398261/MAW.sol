// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./ICamelotRouter.sol";
import "./ICamelotFactory.sol";

interface IControl {
    function addLiquidity() external;
}


contract Control {
    IERC20 public usdt;
    IERC20 public MAW;
    ICamelotRouter public router;
    address public owner;
    constructor(address usdt_, address MAW_, address router_, address owner_) {
        usdt = IERC20(usdt_);
        MAW = IERC20(MAW_);
        router = ICamelotRouter(router_);
        usdt.approve(address(router), type(uint).max);
        MAW.approve(address(router), type(uint).max);
        owner = owner_;

    }
    modifier onlyOwner{
        require(msg.sender == owner, "not owner");
        _;
    }

    function _addliquidity(uint amountA, uint amountB) internal {
        router.addLiquidity(address(usdt), address(MAW), amountA, amountB, 0, 0, address(this), block.timestamp);
    }

    function addLiquidity() external {
        require(msg.sender == address(MAW), 'wrong sender');
        uint tokenAmount = MAW.balanceOf(address(this));
        uint lastUAmount = usdt.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = address(MAW);
        path[1] = address(usdt);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(tokenAmount / 2, 0, path, address(this), address(0), block.timestamp);
        uint newUAmount = usdt.balanceOf(address(this));
        _addliquidity(newUAmount - lastUAmount, tokenAmount / 2);
    }

    function safePull(address token, uint amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}

contract MAWToken is ERC20, Ownable {
    mapping(address => bool) public pairs;
    address constant burnAddress = 0x000000000000000000000000000000000000dEaD;
    IERC20 public usdt;
    uint public swapFee = 1;
    mapping(address => bool) public W;
    uint public swapLimit = 100 ether;
    IControl public control;
    constructor() ERC20("MAW", "MAW") {
        _mint(msg.sender, 100000000 ether);


    }

    function addPair(address pair, bool b) external onlyOwner {
        pairs[pair] = b;
    }

    function setW(address[] memory addrs, bool b) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
            W[addrs[i]] = b;
        }
    }

    function setAddress(address usdt_, address router_) external onlyOwner {
        usdt = IERC20(usdt_);

        address pair = ICamelotFactory(ICamelotRouter(router_).factory()).getPair(address(this), address(usdt));
        if (pair == address(0)) {
            pair = ICamelotFactory(ICamelotRouter(router_).factory()).createPair(address(this), address(usdt));
        }
        pairs[pair] = true;
        address control_;
        W[msg.sender] = true;
        bytes memory code = type(Control).creationCode;
        bytes memory bytecode = abi.encodePacked(code, abi.encode(usdt_, address(this), router_, msg.sender));
        //        bytes32 salt = keccak256(abi.encodePacked(address(this)));
        assembly {
            control_ := create2(0, add(bytecode, 32), mload(bytecode), 77)
        }
        control = IControl(control_);
    }


    function _processTransfer(address from, address to, uint amount) internal {
        if (W[from] || W[to]) {
            _transfer(from, to, amount);
            return;
        }
        if (pairs[from]) {
            uint fee = amount * swapFee / 100;
            _transfer(from, to, amount - fee);
            _transfer(from, address(control), fee);
            return;
        }
        if (pairs[to]) {
            uint fee = amount * swapFee / 100;
            _transfer(from, to, amount - fee);
            _transfer(from, burnAddress, fee);
            return;
        }
        if (balanceOf(address(control)) >= swapLimit) {
            control.addLiquidity();
        }
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

    function safePull(address token, address from, uint amount) external onlyOwner {
        IERC20(token).transferFrom(from, address(this), amount);
    }

}
