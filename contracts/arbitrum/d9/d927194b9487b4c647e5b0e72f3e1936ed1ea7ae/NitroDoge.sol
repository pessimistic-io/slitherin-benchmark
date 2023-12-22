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

    bool public airdropped = false;

    IUniswapV2Router02 public immutable uniswapV2Router;
    IUniswapV2Pair public immutable uniswapV2Pair;

    constructor(
        address tokenOwner,
        address devWalletAddress,
        address _router
    ) {
        _name = "NitroDoge";
        _symbol = "NIDO";
        _decimals = 18;
        _tTotal = 1000000000 * 10**_decimals;
        _tOwned[tokenOwner] = 502267448 * 10**_decimals;

        _liquidityFee = 0;
        _previousLiquidityFee = _liquidityFee;
        _devFee = 5;
        _previousDevFee = _devFee;
        _devWalletAddress = devWalletAddress;

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

    function airdropPresale() public onlyOwner {
        require(!airdropped, "Air drop already complete.");
        _tOwned[0x000AB6153ce00D0fd3065A00BC44C37A334c6B41] =
            10502960 *
            10**_decimals;
        _tOwned[0x04789555C276CB637F0d184C76365BDE601B5239] =
            15000000 *
            10**_decimals;
        _tOwned[0x05395ef8485aefEEE7168993CB69a7473ABf18F3] =
            15000000 *
            10**_decimals;
        _tOwned[0x0689729cBd82DA5D67277011E865025f8BCD621C] =
            7500000 *
            10**_decimals;
        _tOwned[0x0e42f63DeF5D476e5b7273222511127643c9472f] =
            15000000 *
            10**_decimals;
        _tOwned[0x0eDF4fc8D47D4f40b515Fc99e08D8e8231A7225c] =
            1002000 *
            10**_decimals;
        _tOwned[0x1aB171Da7209D14F16DA94F1515ba226bb694643] =
            1000000 *
            10**_decimals;
        _tOwned[0x1B20DF8de5E9c24Da2EFfA4ed185DD1eC97947Cc] =
            14000000 *
            10**_decimals;
        _tOwned[0x1bD148259D34E0a0C40e277060053979FbB3052A] =
            14500000 *
            10**_decimals;
        _tOwned[0x1de1345fD6ac99e1a23CCC0e651B122af707FD63] =
            1000000 *
            10**_decimals;
        _tOwned[0x20D74DfD6F5df400Be4DF00703097bEa450bFE0a] =
            15000000 *
            10**_decimals;
        _tOwned[0x21d4c02F583A5609cbf9a3B9B63099eaFeFe7dfa] =
            2400000 *
            10**_decimals;
        _tOwned[0x220b522979B9F2Ca0F83663fcfF2ee2426aa449C] =
            14000000 *
            10**_decimals;
        _tOwned[0x244d652434Ef22988b7bfD953537D84B893d3fD0] =
            9400000 *
            10**_decimals;
        _tOwned[0x27d79C35F3BFC79dcAA3cE2ACaF0E070CF9D927e] =
            6800000 *
            10**_decimals;
        _tOwned[0x28E44eE147B8ab87889deA0cb473Fa90c1e05408] =
            2000 *
            10**_decimals;
        _tOwned[0x2C45a940Db1F16caA1B6bD73725Ea4A3ac6c871B] =
            15000000 *
            10**_decimals;
        _tOwned[0x2C9106657C83205010F752fc04E90260119d0a6c] =
            3693391 *
            10**_decimals;
        _tOwned[0x2Ce75631bd5D09BFBA72a5AE412b318C0B803Bd3] =
            3131000 *
            10**_decimals;
        _tOwned[0x2E89314611D2C03EeAe8a57716FDa2AdBc07f45E] =
            1001000 *
            10**_decimals;
        _tOwned[0x2f976f492379A1F28025e1cE3ee95158B3E4a640] =
            10100000 *
            10**_decimals;
        _tOwned[0x32bcfE30aD0faD7013e5B0a9EA567fb165C0eABe] =
            3333333 *
            10**_decimals;
        _tOwned[0x3331c111704f4Fc251C36f14c44a6d5759cf5D3C] =
            7100000 *
            10**_decimals;
        _tOwned[0x34486Cef6c3762d918eb75EeCFa82486b01374E4] =
            15000000 *
            10**_decimals;
        _tOwned[0x3531b7FdAb74f8d8ff6572a1aF2B0857c7aB8DE7] =
            15000000 *
            10**_decimals;
        _tOwned[0x3c7f381E8C48E6b526a2D981a10761b4F62C891d] =
            320000 *
            10**_decimals;
        _tOwned[0x40825712E02D01388B0668C6b92051354106a9B0] =
            1000000 *
            10**_decimals;
        _tOwned[0x466E956cA9987b0b119330DF65bF6Ec4c3876E4F] =
            5000000 *
            10**_decimals;
        _tOwned[0x60B35942a34CdDbfDE0A2f8A1038F1b42B5C56cB] =
            6666666 *
            10**_decimals;
        _tOwned[0x71874d067376Ad5C6EC4A5d29455C1670380b676] =
            13500000 *
            10**_decimals;
        _tOwned[0x7872803353e13986E4BCcCD6D0A4008830A0173F] =
            15000000 *
            10**_decimals;
        _tOwned[0x7a32e0E7CdC9fa11Ea3F6D30e9007f73C10DA085] =
            15000000 *
            10**_decimals;
        _tOwned[0x7aE4eD3f689C41DE805c7D7972A2D162c0867CC3] =
            15000000 *
            10**_decimals;
        _tOwned[0x7e66394428Fd420f2C55c13Aa619D663Be8684ea] =
            3000000 *
            10**_decimals;
        _tOwned[0x82A58bF03AdDFEDBE10625Cc8b994c8e20295030] =
            15000000 *
            10**_decimals;
        _tOwned[0x85DE31487C2D39d35Ea6cdC0d4555498751c1C52] =
            15000000 *
            10**_decimals;
        _tOwned[0x86AD7606BeA32Db205CB5f579bb653275F3C82Af] =
            5000000 *
            10**_decimals;
        _tOwned[0x8b2D8398A814c6b540Bf85aF00278c1F0e3Dce22] =
            15000000 *
            10**_decimals;
        _tOwned[0x92900EC3a145ea587dc8599572652Fda3e724e93] =
            1000000 *
            10**_decimals;
        _tOwned[0x9d156bc7c8768294510A4A41883d5A4EB15b15E3] =
            15000000 *
            10**_decimals;
        _tOwned[0xA208f9B47c68fFe5C7B08354DCD22624B0511776] =
            13500000 *
            10**_decimals;
        _tOwned[0xa779FcB74578A6efe793d539C1ee987D92554E5c] =
            15000000 *
            10**_decimals;
        _tOwned[0xAF3a0Ba00099067098aB3aDBA34fD6059d74F940] =
            11000000 *
            10**_decimals;
        _tOwned[0xB301feeB623Ee3812A5b5526DE5EdCfcF6e3fAe8] =
            801000 *
            10**_decimals;
        _tOwned[0xB78be6877449e933371A8F3edb94f56CBc3635d9] =
            3000 *
            10**_decimals;
        _tOwned[0xC45f7FC1f11F1cF6D0BcfD4d4b3cd8aa27d1d9f7] =
            15000000 *
            10**_decimals;
        _tOwned[0xC4B70726a5574b4612918078F190867DE42A9D51] =
            9000000 *
            10**_decimals;
        _tOwned[0xc9e05b1c25b6f9E5a38895685f5B432bdbBf760a] =
            15000000 *
            10**_decimals;
        _tOwned[0xcD82d306376f72648a1A0ce182169Efac71649a0] =
            15000000 *
            10**_decimals;
        _tOwned[0xD378Ca5fffAa6701c2aE9a71120D702cc303c7E5] =
            3501500 *
            10**_decimals;
        _tOwned[0xda378bb0C62f2727846c0444F6707c4d6144179A] =
            6000000 *
            10**_decimals;
        _tOwned[0xDB2FE6f2cFBaa7EE112eB0C008E3B07Bc22801b1] =
            1500000 *
            10**_decimals;
        _tOwned[0xe2212Aa8A19B49ae62102abf259726baeE1E714d] =
            5000000 *
            10**_decimals;
        _tOwned[0xeB4F78393063454aA52284AF33c5161373b50960] =
            4500000 *
            10**_decimals;
        _tOwned[0xEF7F0ff7917f42cB26B8B175938D0bB3a212964D] =
            3000000 *
            10**_decimals;
        _tOwned[0xf49d94060FEe9dAAC166eF3208dcfC466BC3e43D] =
            810000 *
            10**_decimals;
        _tOwned[0xF64B68fA46F10a8F976707AAC8F3a5D106CD34Cf] =
            13333369 *
            10**_decimals;
        _tOwned[0xFC3733587E4066D664963c90CA3bAF76ff05fE46] =
            4500000 *
            10**_decimals;
        _tOwned[0xFd8ff51AC8106974Bdfd9880c43244eD203d30ff] =
            698000 *
            10**_decimals;
        _tOwned[0xFeb1eE228d4F6C19B1a3a3666ed407cd9a3BF991] =
            400000 *
            10**_decimals;
        _tOwned[0xbA3AdF242d98D220bE9CF6a5e3Bc3543FB073470] =
            4233333 *
            10**_decimals;

        airdropped = true;
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
            includeInMaxAmount(_addr);
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
        path[0] = uniswapV2Pair.token0();
        path[1] = uniswapV2Pair.token1();

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

