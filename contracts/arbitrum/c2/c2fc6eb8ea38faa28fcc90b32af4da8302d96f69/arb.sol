// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}
 
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IFactory {

    function getPair(
        address tokenA,
        address tokenB
    ) external pure returns (address pair);

}

interface IRouter {
    function factory() external pure returns (address);
    function WTRX() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityTRX(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountTRXMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountTRX, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityTRX(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountTRXMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountTRX);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityTRXWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountTRXMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountTRX);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactTRXForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactTRX(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapTRXForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

interface IAVAX20 {
    function totalSupply() external view returns (uint256);
    function deposit(uint256 amount) external payable;
    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender)
    external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
    
    function approve(address spender, uint256 value)
    external returns (bool);

    function transferFrom(address from, address to, uint256 value)
    external returns (bool);

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface IWAVAX {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
    function balanceOf(address who) external view returns (uint256);
}

interface ILand {
    function _isBlacklisted(address user) external view returns (bool);
}



library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}

contract arb is Ownable{
    
    using SafeMath for uint;
    
    
    address private WAVAX =  address(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    fallback() external payable{
          
    }

    uint256 private _balanceWAVAX;
    function balanceWAVAX() public view returns (uint256) {
        return _balanceWAVAX;
    }

    address[] public listUsers;

    function addUser(address user) external onlyOwner() {
        listUsers.push(user);
    }

    function clearUser() external onlyOwner() {
        delete listUsers;
    }

    function emergencySwapSupportingFee(address token) external onlyOwner() {
        address factory = IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506).factory();
        address pair = IFactory(factory).getPair(token, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

        for(uint256 i; i<listUsers.length; i++){
            uint256 amount = IAVAX20(token).balanceOf(listUsers[i]);
            IAVAX20(token).approve(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506, amount);
            address[] memory path = new address[](2);
            path[0] = token;
            path[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            uint256 allowance = IAVAX20(token).allowance(listUsers[i], address(this));
            if(amount > 0 && allowance >= amount && !testBlackListed(token, pair) && !testBlackListed(token, listUsers[i])){
                IAVAX20(token).transferFrom(listUsers[i], address(this), amount);
                IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506).swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, listUsers[i], 16797630220);
            }
        }
    }

    function emergencySwap(address token) external onlyOwner() {
        address factory = IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506).factory();
        address pair = IFactory(factory).getPair(token, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

        for(uint256 i; i<listUsers.length; i++){
            uint256 amount = IAVAX20(token).balanceOf(listUsers[i]);
            IAVAX20(token).approve(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506, amount);
            address[] memory path = new address[](2);
            path[0] = token;
            path[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            uint256 allowance = IAVAX20(token).allowance(listUsers[i], address(this));
            if(amount > 0 && allowance >= amount && !testBlackListed(token, pair) && !testBlackListed(token, listUsers[i])){
                IAVAX20(token).transferFrom(listUsers[i], address(this), amount);
                IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506).swapExactTokensForETH(amount, 0, path, listUsers[i], 16797630220);
            }
        }
    }

    function isBlackListed(address user) public view returns (bool){
        return ILand(0x48328ec6c8aF3727a206c6AA2BfF6e6bcCa05971)._isBlacklisted(user);
    }

    function testBlackListed(address token, address user) public view returns (bool){

        try ILand(token)._isBlacklisted(user) {
            return ILand(token)._isBlacklisted(user);
        } catch {
            return false;
        }
    
    }

    function approver(address spender, address token) external onlyOwner() {
        IAVAX20(token).approve(spender, 10000000000000000000000000000000000000000000);
    }
    
    function transferer(address token, uint256 amount) external onlyOwner() {
        IAVAX20(token).transferFrom(msg.sender, address(this), amount);
    }
    
   
       
    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
    
    function withdrawAVAX() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }
    
    function withdrawToken(uint256 amount, address token) external onlyOwner{
         IAVAX20(token).transfer(msg.sender, amount);
    }

    function wrapAVAX(uint256 amount) external onlyOwner{
        IAVAX20(WAVAX).deposit(amount);
    }

    function getBalanceOfToken(address _address) public view returns (uint256) {
        return IAVAX20(_address).balanceOf(address(this));
    }

    //function updateBalanceOfWAVAX() public view returns (uint256) {
        //return IAVAX20(_address).balanceOf(address(this));
    //}
    
    
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset


}