//SPDX-License-Identifier: ZEPTO
pragma solidity ^0.8.0;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./AccessControlEnumerable.sol";

contract LearnToEarnToken  is ERC20Burnable, Ownable, AccessControlEnumerable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    using SafeMath for uint;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) public ammPairs;

    uint256 private _totalFee;
    uint256 public constant MAX_FEE_PERCENTAGE = 100; // 10 %
    uint256 public constant FEE_PRECISION = 1000; // 100%
    uint256 public _buyTaxFee = 70; // 7%
    uint256 public _sellTaxFee = 30; // 3%

    address public beneficiary;

    address public minter;

    event FeeDistributedEvent(address beneficiary, uint fee);

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Invalid operator");
        _;
    }
      modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Invalid minter");
        _;
    }

    constructor (address tokenOwner, address _beneficiary) ERC20("Learn to earn", "$LEARN") {
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        beneficiary = _beneficiary;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, tokenOwner);
        _mint(tokenOwner, 100_000_000 ether); // 100.000.000 $LEARN
    }

    fallback () external payable {
        revert(); // Not allow sending BNB to this contract
    }

    receive() external payable {
        revert(); // Not allow sending BNB to this contract
    }

    function mint(address recipient, uint256 amount) public onlyMinter() {
        _mint(recipient, amount);
    }
    function _transfer(address sender, address recipient, uint256 amount) internal override {

        bool takeFee = true;
        if(_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
            takeFee = false;
        }
        _tokenTransfer(sender, recipient, amount, takeFee);
    }

    function _getTaxFee(address sender, address recipient, bool takeFee) private view returns (uint){
        uint _taxFee = 0;
        if(takeFee) {
            bool isBuy = ammPairs[sender];
            bool isSell = ammPairs[recipient];
            if(isBuy){
                _taxFee = _buyTaxFee;
            } else if(isSell){
                _taxFee = _sellTaxFee;
            }
        }
        return _taxFee;
    }

    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {

        uint _taxFee = _getTaxFee(sender, recipient, takeFee);
        (uint actualAmount, uint fee) = _getValues(amount, _taxFee);
        super._transfer(sender, recipient, actualAmount);

        if(fee > 0) {
            super._transfer(sender, beneficiary, fee);
            _totalFee = _totalFee.add(fee);
            emit FeeDistributedEvent(beneficiary, fee);
        }
    }

    /**
       Calculate actual amount recipient will receive and fee to beneficiary
    */
    function _getValues(uint256 transferAmount, uint taxFee) private pure returns (uint256, uint256) {

        if(taxFee == 0) {
            return (transferAmount, 0);
        }

        uint fee =  transferAmount.mul(taxFee).div(FEE_PRECISION);
        uint256 actualAmount = transferAmount.sub(fee);
        return (actualAmount, fee);
    }


    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }


    function totalFees() public view returns (uint256) {
        return _totalFee;
    }

    function setTaxFeePercent(uint256 buyTaxFee, uint256 sellTaxFee) external onlyOperator {
        require(buyTaxFee <= MAX_FEE_PERCENTAGE, "Buy Tax Fee reached the maximum limit");
        require(sellTaxFee <= MAX_FEE_PERCENTAGE, "Sell Tax Fee reached the maximum limit");
        _buyTaxFee = buyTaxFee;
        _sellTaxFee = sellTaxFee;
    }

    function addExcludesFee(address[] calldata accounts) public onlyOperator {
        for(uint i = 0 ; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = true;
        }
    }

    function removeExcludesFee(address[] calldata accounts) public onlyOperator {
        for(uint i = 0 ; i < accounts.length; i++) {
           delete _isExcludedFromFee[accounts[i]];
        }
    }

    function changeBeneficiary(address newBeneficiary) public onlyOperator {
        beneficiary = newBeneficiary;
    }


    function addAmmPairs(address[] calldata pairs) public onlyOperator {

        for(uint i = 0; i < pairs.length; i++) {
            ammPairs[pairs[i]] = true;
        }
    }
    
    function changeMinter(address newMinter) public onlyOperator {
        //require(minter == address(0), "Minter already configured");
        // enable for prod
        minter = newMinter;
    }

}


