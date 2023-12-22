// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

contract NitroDoge is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    address public router;
    address public basePair;

    uint256 public prevLiqFee;
    uint256 public prevDevFee;

    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcludedFromMaxAmount;
    mapping(address => bool) private _isDevWallet;

    address[] private _excluded;
    address public _devWalletAddress;

    uint256 private _tTotal;

    uint256 public _liquidityFee;
    uint256 private _previousLiquidityFee = _liquidityFee;

    uint256 public _devFee;
    uint256 private _previousDevFee = _devFee;

    uint256 public _maxTxAmount;
    uint256 public _maxHeldAmount;

    IUniswapV2Router02 public immutable uniswapV2Router;
    IUniswapV2Pair public immutable uniswapV2Pair;

    constructor(
        address tokenOwner,
        address devWalletAddress_,
        address _router
    ) {
        _name = "NitroDoge";
        _symbol = "NIDO";
        _decimals = 18;
        _tTotal = 1000000000 * 10**_decimals;
        _tOwned[tokenOwner] = _tTotal;

        _liquidityFee = 0;
        _previousLiquidityFee = _liquidityFee;
        _devFee = 5;
        _previousDevFee = _devFee;
        _devWalletAddress = devWalletAddress_;

        _maxHeldAmount = _tTotal.mul(15).div(1000); // 1.5%
        _maxTxAmount = _maxHeldAmount; // same as max held

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Pair(
            IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
                address(this),
                _uniswapV2Router.WETH()
            )
        );

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_devWalletAddress] = true;
        _isExcludedFromMaxAmount[owner()] = true;
        _isExcludedFromMaxAmount[address(this)] = true;
        _isExcludedFromMaxAmount[_devWalletAddress] = true;

        //set wallet provided to true
        _isDevWallet[_devWalletAddress] = true;

        emit Transfer(address(0), tokenOwner, _tTotal);
    }

    function getWrapAddr() public view returns (address) {
        return basePair;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _tOwned[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address _owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[_owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function excludeFromFee(address account) public onlyOwner {
        require(!_isExcludedFromFee[account], "Account is already excluded");
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        require(_isExcludedFromFee[account], "Account is already included");
        _isExcludedFromFee[account] = false;
    }

    function excludeFromMaxAmount(address account) public onlyOwner {
        require(
            !_isExcludedFromMaxAmount[account],
            "Account is already excluded"
        );
        _isExcludedFromMaxAmount[account] = true;
    }

    function includeInMaxAmount(address account) public onlyOwner {
        require(
            _isExcludedFromMaxAmount[account],
            "Account is already included"
        );
        _isExcludedFromMaxAmount[account] = false;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        require(liquidityFee >= 0, "liquidityFee out of range");
        _liquidityFee = liquidityFee;
    }

    function setDevFeePercent(uint256 devFee) external onlyOwner {
        require(devFee >= 0, "teamFee out of range");
        _devFee = devFee;
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        require(maxTxPercent <= 100, "maxTxPercent out of range");
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**2);
    }

    function setDevWalletAddress(address _addr) public onlyOwner {
        require(!_isDevWallet[_addr], "Wallet address already set");
        if (!_isExcludedFromFee[_addr]) {
            excludeFromFee(_addr);
        }
        _isDevWallet[_addr] = true;
        _devWalletAddress = _addr;
    }

    function replaceDevWalletAddress(address _addr, address _newAddr)
        external
        onlyOwner
    {
        require(_isDevWallet[_addr], "Wallet address not set previously");
        if (_isExcludedFromFee[_addr]) {
            includeInFee(_addr);
        }
        _isDevWallet[_addr] = false;
        if (_devWalletAddress == _addr) {
            setDevWalletAddress(_newAddr);
        }
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tDev = calculateDevFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tLiquidity).sub(tDev);
        return (tTransferAmount, tLiquidity, tDev);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    function _takeDev(uint256 tDev) private {
        _tOwned[_devWalletAddress] = _tOwned[_devWalletAddress].add(tDev);
    }

    function calculateLiquidityFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        return _amount.mul(_liquidityFee).div(10**2);
    }

    function calculateDevFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_devFee).div(10**2);
    }

    function removeAllFee() private {
        if (_liquidityFee == 0 && _devFee == 0) return;

        _previousLiquidityFee = _liquidityFee;
        _previousDevFee = _devFee;

        _liquidityFee = 0;
        _devFee = 0;
    }

    function restoreAllFee() private {
        _liquidityFee = _previousLiquidityFee;
        _devFee = _previousDevFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function isExcludedFromMaxAmount(address account)
        public
        view
        returns (bool)
    {
        return _isExcludedFromMaxAmount[account];
    }

    function _approve(
        address _owner,
        address spender,
        uint256 amount
    ) private {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][spender] = amount;
        emit Approval(_owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        // Only limit max TX for swaps, not for standard transactions
        if (
            from == address(uniswapV2Router) || to == address(uniswapV2Router)
        ) {
            if (
                !_isExcludedFromMaxAmount[from] && !_isExcludedFromMaxAmount[to]
            )
                require(
                    amount <= _maxTxAmount,
                    "Transfer amount exceeds the maxTxAmount."
                );
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        if (!_isExcludedFromMaxAmount[to]) {
            require(
                _tOwned[to].add(amount) <= _maxHeldAmount,
                "Recipient already owns maximum amount of tokens."
            );
        }

        //transfer amount, it will take dev, liquidity fee
        _tokenTransfer(from, to, amount, takeFee);

        //reset tax fees
        restoreAllFee();
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> WHT
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = getWrapAddr();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ETHAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity

        uniswapV2Router.addLiquidityETH{value: ETHAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            DEAD,
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        (
            uint256 tTransferAmount,
            uint256 tLiquidity,
            uint256 tDev
        ) = _getValues(amount);
        _tOwned[sender] = _tOwned[sender].sub(amount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeDev(tDev);

        emit Transfer(sender, recipient, tTransferAmount);
    }

    function disableFees() public onlyOwner {
        prevLiqFee = _liquidityFee;
        prevDevFee = _devFee;

        _liquidityFee = 0;
        _devFee = 0;
    }

    function enableFees() public onlyOwner {
        _liquidityFee = prevLiqFee;
        _devFee = prevDevFee;
    }
}

