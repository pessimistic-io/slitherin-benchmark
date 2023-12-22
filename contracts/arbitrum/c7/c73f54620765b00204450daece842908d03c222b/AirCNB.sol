//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./Address.sol";

contract AirCNB is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => uint256) private _owned;
    mapping(address => bool) public pools;

    uint256 private _totalSupply = 4_200_000_000 * 10**18;
    string private _name = 'Air CNB V1';
    string private _symbol = 'AIRCNBV1';
    uint8 private _decimals = 18;

    // Buy Fees
    uint256 public _team = 1;
    uint256 private _burn = 1;
    uint256 public _pool = 1;
    uint256 private _nft = 1;
    
    // Sell Fees
    uint256 public _sTeam = 1;
    uint256 private _sBurn = 1;
    uint256 public _sPool = 1;
    uint256 private _sNft = 1;

    // Wallets
    address public _teamWallet;
    address public _poolWallet;
    address public _nftWallet;

    uint256 public _totalBuyFee;
    uint256 public _totalSellFee;

    // Anti whale
    uint256 public constant MAX_HOLDING_PERCENTS_DIVISOR = 1000;
    uint256 public _maxHoldingPercents = 5;
    bool public antiWhaleEnabled;
    

    constructor(
    ) {
        _owned[_msgSender()] = _totalSupply;

        // Create a pancake pair for this new token

        //exclude owner, anti manager and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        _totalBuyFee = _team + _burn + _pool + _nft;
        _totalSellFee = _sTeam + _sBurn + _sPool + _sNft;
        
        emit Transfer(address(0), _msgSender(), _totalSupply);
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
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _owned[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function burn(uint256 amount) public {
        _baseTransfer(_msgSender(), address(0), amount);
        emit Transfer(_msgSender(), address(0), amount);
    }

    function burnFrom(address _from, uint256 _amount) public {
        require(_allowances[_from][_msgSender()] >= _amount, 'Error amount to burn');
        _approve(
            _from,
            _msgSender(),
            _allowances[_from][_msgSender()].sub(_amount, 'BEP20: burn amount exceeds allowance')
        );
        _baseTransfer(_from, address(0), _amount);
        emit Transfer(_from, address(0), _amount);
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
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
                'BEP20: transfer amount exceeds allowance'
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
                'BEP20: decreased allowance below zero'
            )
        );
        return true;
    }
    
    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), 'BEP20: approve from the zero address');
        require(spender != address(0), 'BEP20: approve to the zero address');

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), 'BEP20: transfer from the zero address');
        require(amount > 0, 'Transfer amount must be greater than zero');

        //transfer amount, it will take fee
        _tokenTransfer(from, to, amount);

        if (antiWhaleEnabled) {
            uint256 maxAllowed = (_totalSupply * _maxHoldingPercents) /
                MAX_HOLDING_PERCENTS_DIVISOR;
            if (pools[to]) {
                require(
                    amount <= maxAllowed,
                    'Transacted amount exceed the max allowed value'
                );
            } else {
                require(
                    balanceOf(to) <= maxAllowed,
                    'Wallet balance exceeds the max limit'
                );
            }
        }
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        if (pools[sender] && !_isExcludedFromFee[recipient]) {
            uint256 teamAmount = _getFeeAmount(amount, _team);
            uint256 poolAmount = _getFeeAmount(amount, _pool);
            uint256 nftAmount = _getFeeAmount(amount, _nft);
            uint256 burnAmount = _getFeeAmount(amount, _burn);

            _baseTransfer(sender, _teamWallet, teamAmount);
            _baseTransfer(sender, _poolWallet, poolAmount);
            _baseTransfer(sender, _nftWallet, nftAmount);
            _baseTransfer(sender, address(0), burnAmount);
            amount = amount - teamAmount - poolAmount - nftAmount - burnAmount;
            _baseTransfer(sender, recipient, amount);
        } else if (pools[recipient] && !_isExcludedFromFee[sender]) {
            uint256 teamAmount = _getFeeAmount(amount, _sTeam);
            uint256 poolAmount = _getFeeAmount(amount, _sPool);
            uint256 nftAmount = _getFeeAmount(amount, _sNft);
            uint256 burnAmount = _getFeeAmount(amount, _sBurn);

            _baseTransfer(sender, _teamWallet, teamAmount);
            _baseTransfer(sender, _poolWallet, poolAmount);
            _baseTransfer(sender, _nftWallet, nftAmount);
            _baseTransfer(sender, address(0), burnAmount);
            amount = amount - teamAmount - poolAmount - nftAmount - burnAmount;
            _baseTransfer(sender, recipient, amount);
        } else {
            _baseTransfer(sender, recipient, amount);
        }
    }

    function _getFeeAmount(uint256 _amount, uint256 _type) private pure returns(uint256) {
        return _amount.div(1000).mul(_type);
    }

    function _baseTransfer(address sender, address recipient, uint256 amount) private {
        _owned[sender] = _owned[sender].sub(amount);
        _owned[recipient] = _owned[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }
    
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setMaxHoldingPercents(uint256 maxHoldingPercents) external onlyOwner {
        require(maxHoldingPercents >= 1, 'Max holding percents cannot be less than 0.1%');
        require(maxHoldingPercents <= 30, 'Max holding percents cannot be more than 3%');
        _maxHoldingPercents = maxHoldingPercents;
    }

    function setAntiWhale(bool enabled) external onlyOwner {
        antiWhaleEnabled = enabled;
    }

    function setTeamWallet(address _wallet) external onlyOwner {
        _teamWallet = _wallet;
    }

    function setPoolWallet(address _wallet) external onlyOwner {
        _poolWallet = _wallet;
    }

    function setNftWallet(address _wallet) external onlyOwner {
        _nftWallet = _wallet;
    }

    function setTeamFeePercent(uint256 _amount) external onlyOwner {
        _team = _amount;
        _totalBuyFee = _team + _burn + _pool + _nft;
        require(_totalBuyFee <= 100, 'Error total fee amount');
    }

    function setBurnFeePercent(uint256 _amount) external onlyOwner {
        _burn = _amount;
        _totalBuyFee = _team + _burn + _pool + _nft;
        require(_totalBuyFee <= 100, 'Error total fee amount');
    }

    function setPoolFeePercent(uint256 _amount) external onlyOwner {
        _pool = _amount;
        _totalBuyFee = _team + _burn + _pool + _nft;
        require(_totalBuyFee <= 100, 'Error total fee amount');
    }

    function setNftFeePercent(uint256 _amount) external onlyOwner {
        _nft = _amount;
        _totalBuyFee = _team + _burn + _pool + _nft;
        require(_totalBuyFee <= 100, 'Error total fee amount');
    }

    function setSellTeamFeePercent(uint256 _amount) external onlyOwner {
        _sTeam = _amount;
        _totalSellFee = _sTeam + _sBurn + _sPool + _sNft;
        require(_totalSellFee <= 100, 'Error total fee amount');
    }

    function setSellBurnFeePercent(uint256 _amount) external onlyOwner {
        _sBurn = _amount;
        _totalSellFee = _sTeam + _sBurn + _sPool + _sNft;
        require(_totalSellFee <= 100, 'Error total fee amount');
    }

    function setSellPoolFeePercent(uint256 _amount) external onlyOwner {
        _sPool = _amount;
        _totalSellFee = _sTeam + _sBurn + _sPool + _sNft;
        require(_totalSellFee <= 100, 'Error total fee amount');
    }

    function setSellNftFeePercent(uint256 _amount) external onlyOwner {
        _sNft = _amount;
        _totalSellFee = _sTeam + _sBurn + _sPool + _sNft;
        require(_totalSellFee <= 100, 'Error total fee amount');
    }

    function addPoolAddress(address _address) external onlyOwner {
        pools[_address] = true;
    }

    function removePoolAddress(address _address) external onlyOwner {
        pools[_address] = false;
    }
}

