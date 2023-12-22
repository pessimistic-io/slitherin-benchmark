//SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ECDSAUpgradeable.sol";

interface Aggregator {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract AccruPresale_V2 is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable
{
    using ECDSAUpgradeable for bytes32;

    uint256 public constant baseDecimals = 10 ** 18;
    uint256 public usdRaised;
    uint256 public privateSaleTotalSold;
    uint256 public publicSale1TotalSold;
    uint256 public publicSale2TotalSold;
    uint256[][3] public stages;
    bool public isPurchaseLimitEnable;
    address public paymentWallet;
    address public signer;

    enum saleStage {
        privateSale,
        publicSale1,
        publicSale2
    }
    saleStage public saleStages;

    Aggregator public aggregatorInterface;
    mapping(address => uint) public nonces;
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public privateSaleDeposits;
    mapping(address => uint256) public publicSale1Deposits;
    mapping(address => uint256) public publicSale2Deposits;

    uint256 private maxPurchase;
    uint256 private privateSaleMinPurchase;
    uint256 private publicSale1MinPurchase;
    uint256 private publicSale2MinPurchase;
    uint256 public reserveTotalSold;

    // Events
    event TokensBought(
        address indexed user,
        uint256 indexed tokensBought,
        uint256 pricePaid,
        uint256 usdEq,
        uint256 timestamp
    );
    event UpdatePaymentWallet(address indexed paymentWallet);
    event ChangeSaleStage(saleStage stage);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initializes the contract and sets key parameters
     * @param _stages array of stages detail
     * @param _oracle Oracle contract to fetch ETH/USD price
     * @param _paymentWallet address to recive payments
     * @param _signer signer to validate signature
     */
    function initialize(
        uint256[][3] memory _stages,
        address _oracle,
        address _paymentWallet,
        address _signer
    ) external initializer {
        require(_oracle != address(0), "Zero aggregator address");
        __Pausable_init_unchained();  
        __Ownable_init_unchained();  
        __ReentrancyGuard_init_unchained();  
        maxPurchase = 333333333;  
        privateSaleMinPurchase = 33333333;  
        publicSale1MinPurchase = 4444444;
        publicSale2MinPurchase = 3636363;
        isPurchaseLimitEnable = true;
        stages = _stages;
        aggregatorInterface = Aggregator(_oracle);
        paymentWallet = _paymentWallet;
        signer = _signer;
    }

    // modifier
    modifier checkSaleState(uint256 amount, uint8 stage) {
        require(amount > 0, "Invalid sale amount");
        require(
            block.timestamp >= stages[stage][0] &&
                block.timestamp <= stages[stage][1],
            "Invalid time for buying"
        );
        _;
    }

    modifier checkPurchaseAmount(uint256 amount) {
        uint256 totalAmount = stages[0][2] + stages[1][2] + stages[2][2];
        uint256 totalSold = privateSaleTotalSold +
            publicSale1TotalSold +
            publicSale2TotalSold +
            reserveTotalSold;
        require(
            totalSold + amount <= totalAmount && amount > 0,
            "Invalid sale amount"
        );
        _;
    }

    /**
     * @dev To pause the presale
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev To unpause the presale
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev To calculate the price in USD for given amount of tokens.
     * @param _amount No of tokens
     */
    function calculatePrice(uint256 _amount) public view returns (uint256) {
        saleStage stage = saleStages;
        uint256 price;
        if (stage == saleStage.privateSale) {
            price = _amount * stages[0][3];
            return price;
        } else if (stage == saleStage.publicSale1) {
            price = _amount * stages[1][3];
            return price;
        }
        price = _amount * stages[2][3];
        return price;
    }

    // Verify purchase limit for different sale

    function verifyPrivateSalePurchase(
        address account,
        uint256 amount
    ) public view returns (bool) {
        uint256 purchasedAmount = privateSaleDeposits[account] / baseDecimals;
        if (
            purchasedAmount >= privateSaleMinPurchase &&
            purchasedAmount + amount <= maxPurchase
        ) {
            return true;
        }
        return (amount >= privateSaleMinPurchase && amount <= maxPurchase);
    }

    function verifyPublicSale1Purchase(
        address account,
        uint256 amount
    ) public view returns (bool) {
        uint256 purchasedAmount = publicSale1Deposits[account] / baseDecimals;
        return (amount >= publicSale1MinPurchase || purchasedAmount + amount >= publicSale1MinPurchase);   
    }

    function verifyPublicSale2Purchase(
        address account,
        uint256 amount
    ) public view returns (bool) {
        uint256 purchasedAmount = publicSale2Deposits[account] / baseDecimals;
        return (amount >= publicSale2MinPurchase || purchasedAmount + amount >= publicSale2MinPurchase);
    }

    /**
     * @dev To buy token in a private sale using ETH
     * @param amount No of tokens to buy
     */
    function privateSaleTokenBuy(
        uint256 amount,
        bytes calldata sig
    )
        external
        payable
        checkSaleState(amount, uint8(saleStage.privateSale))
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(saleStages == saleStage.privateSale, "Sale not active");

        address sigRecover = keccak256(abi.encodePacked(_msgSender(), amount, nonces[_msgSender()]))
            .toEthSignedMessageHash()
            .recover(sig);
        require(sigRecover == signer, "Invalid signer");

        privateSaleTotalSold += amount;
        require(
            privateSaleTotalSold <= stages[0][2],
            "Amount exceeds max token to buy"
        );

        uint256 usdPrice = calculatePrice(amount);
        uint256 ethAmount = (usdPrice * baseDecimals) / getLatestPrice();
        require(msg.value >= ethAmount, "Less payment");
        uint256 excess = msg.value - ethAmount;
        if(isPurchaseLimitEnable) {
            require(
            verifyPrivateSalePurchase(_msgSender(), amount),
            "Invalid purchased"
            );
        }

        nonces[_msgSender()]++;
        privateSaleDeposits[_msgSender()] += (amount * baseDecimals);
        userDeposits[_msgSender()] += (amount * baseDecimals);
        usdRaised += usdPrice;
        sendValue(payable(paymentWallet), ethAmount);
        if (excess > 0) sendValue(payable(_msgSender()), excess);

        emit TokensBought(
            _msgSender(),
            amount,
            ethAmount,
            usdPrice,
            block.timestamp
        );
        return true;
    }

    /**
     * @dev To buy token in a public sale1 using ETH
     * @param amount No of tokens to buy
     */
    function publicSale1TokenBuy(
        uint256 amount,
        bytes calldata sig
    )
        external
        payable
        checkSaleState(amount, uint8(saleStage.publicSale1))
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(saleStages == saleStage.publicSale1, "Sale not active");

        address sigRecover = keccak256(abi.encodePacked(_msgSender(), amount, nonces[_msgSender()]))
            .toEthSignedMessageHash()
            .recover(sig);
        require(sigRecover == signer, "Invalid signer");

        publicSale1TotalSold += amount;
        require(
            publicSale1TotalSold <= stages[1][2],
            "Amount exceeds max token to buy"
        );

        uint256 usdPrice = calculatePrice(amount);
        uint256 ethAmount = (usdPrice * baseDecimals) / getLatestPrice();
        require(msg.value >= ethAmount, "Less payment");
        uint256 excess = msg.value - ethAmount;
        if(isPurchaseLimitEnable) {
            require(
            verifyPublicSale1Purchase(_msgSender(), amount),
            "Invalid purchased"
            );
        }
        
        nonces[_msgSender()]++;
        publicSale1Deposits[_msgSender()] += (amount * baseDecimals);
        userDeposits[_msgSender()] += (amount * baseDecimals);
        usdRaised += usdPrice;
        sendValue(payable(paymentWallet), ethAmount);
        if (excess > 0) sendValue(payable(_msgSender()), excess);

        emit TokensBought(
            _msgSender(),
            amount,
            ethAmount,
            usdPrice,
            block.timestamp
        );
        return true;
    }

    /**
     * @dev To buy token in a public sale2 using ETH
     * @param amount No of tokens to buy
     */
    function publicSale2TokenBuy(
        uint256 amount,
        bytes calldata sig
    )
        external
        payable
        checkSaleState(amount, uint8(saleStage.publicSale2))
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(saleStages == saleStage.publicSale2, "Sale not active");

        address sigRecover = keccak256(abi.encodePacked(_msgSender(), amount, nonces[_msgSender()]))
            .toEthSignedMessageHash()
            .recover(sig);
        require(sigRecover == signer, "Invalid signer");

        publicSale2TotalSold += amount;
        require(
            publicSale2TotalSold <= stages[2][2],
            "Amount exceeds max token to buy"
        );

        uint256 usdPrice = calculatePrice(amount);
        uint256 ethAmount = (usdPrice * baseDecimals) / getLatestPrice();
        require(msg.value >= ethAmount, "Less payment");
        uint256 excess = msg.value - ethAmount;
        if (isPurchaseLimitEnable) {
            require(
            verifyPublicSale2Purchase(_msgSender(), amount),
            "Invalid purchased"
            );
        }

        nonces[_msgSender()]++;
        publicSale2Deposits[_msgSender()] += (amount * baseDecimals);
        userDeposits[_msgSender()] += (amount * baseDecimals);
        usdRaised += usdPrice;
        sendValue(payable(paymentWallet), ethAmount);
        if (excess > 0) sendValue(payable(_msgSender()), excess);

        emit TokensBought(
            _msgSender(),
            amount,
            ethAmount,
            usdPrice,
            block.timestamp
        );
        return true;
    }

    /**
     * @dev Owner can buy token for account address
     * @param account Address to which token buy
     * @param amount No of tokens to buy
     * @param value Price of token
     */
    function reserveBuy(
        address account,
        uint256 amount,
        uint256 value
    ) external checkPurchaseAmount(amount) onlyOwner returns (bool) {
        uint256 usdPrice = amount * value;
        userDeposits[account] += (amount * baseDecimals);
        usdRaised += usdPrice;
        reserveTotalSold += amount;

        emit TokensBought(account, amount, 0, usdPrice, block.timestamp);
        return true;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Low balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH Payment failed");
    }

    /**
     * @dev To set payment wallet address
     * @param _newPaymentWallet new payment wallet address
     */
    function changePaymentWallet(address _newPaymentWallet) external onlyOwner {
        require(_newPaymentWallet != address(0), "address cannot be zero");
        paymentWallet = _newPaymentWallet;
        emit UpdatePaymentWallet(_newPaymentWallet);
    }

    /**
     * @dev To get latest ETH price in 10**18 format
     */
    function getLatestPrice() public view returns (uint256) {
        (, int256 price, , , ) = aggregatorInterface.latestRoundData();
        price = (price * (10 ** 10));
        return uint256(price);
    }

    /**
     * @dev To get array of stage details at once
     * @param _index array index
     */
    function stageDetails(
        uint256 _index
    ) external view returns (uint256[] memory) {
        return stages[_index];
    }

    /**
     * @dev Helper funtion to get ETH price for given amount
     * @param amount No of tokens to buy
     */
    function ethBuyHelper(
        uint256 amount
    ) external view returns (uint256 ethAmount) {
        uint256 usdPrice = calculatePrice(amount);
        ethAmount = (usdPrice * baseDecimals) / getLatestPrice();
    }

    /**
     * @dev To set sale stage
     * @param _stage sale stage
     */
    function setSaleStage(saleStage _stage) external onlyOwner {
        require(_stage > saleStages, "sale is already started");
        saleStages = _stage;
        emit ChangeSaleStage(_stage);
    }

    /**
     * @dev To set stages data
     * @param _stages sale stages
     */
    function changeStagesData(uint256[][3] memory _stages) external onlyOwner {
        stages = _stages;
    }

    /**
     * @dev To change signer wallet address
     * @param _signer new signer wallet address
     */
    function setSignerWallet(address _signer) external onlyOwner {
        signer = _signer;
    }

    /**
     * @dev To set purchase limit enable or disable
     * @param _status purchase status
     */
    function setPurchaseLimitStatus(bool _status) external onlyOwner {
        isPurchaseLimitEnable = _status;
    }

    // Change all sales minimum purchase amount of token

    function setPrivateSaleMinPurchase(uint256 _minAmount) external onlyOwner {
        privateSaleMinPurchase = _minAmount;
    }

    function setPublicSale1MinPurchase(uint256 _minAmount) external onlyOwner {
        publicSale1MinPurchase = _minAmount;
    }

    function setPublicSale2MinPurchase(uint256 _minAmount) external onlyOwner {
        publicSale2MinPurchase = _minAmount;
    }

    /**
     * @dev To change maximum purchase amount of token
     * @param _maxAmount maximum purchase amount
     */
    function setMaxPurchase(uint256 _maxAmount) external onlyOwner {
        maxPurchase = _maxAmount;
    }
}
