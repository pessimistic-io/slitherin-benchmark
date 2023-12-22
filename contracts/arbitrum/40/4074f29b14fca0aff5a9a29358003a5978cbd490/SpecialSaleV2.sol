//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

contract SpecialSaleV2 is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using ECDSAUpgradeable for bytes32;

    uint256 public constant baseDecimals = 10 ** 18;
    uint256 public usdRaised;
    uint256 public privateSale1TotalSold;
    uint256 public privateSale2TotalSold;
    uint256 public minTokenToBuy;
    uint256[][4] public stages;
    address public paymentWallet;
    address public signer;

    enum saleStage {
        privateSale1,
        privateSale2,
        preSale,
        publicSale
    }
    saleStage public saleStages;

    Aggregator public aggregatorInterface;
    mapping(address => uint256) public nonces;
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public privateSale1Deposits;
    mapping(address => uint256) public privateSale2Deposits;

    uint256 public preSaleTotalSold;
    uint256 public publicSaleTotalSold;
    mapping(address => uint256) public preSaleDeposits;
    mapping(address => uint256) public publicSaleDeposits;
    mapping(address => address) public userRef;

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
     * @param _minTokenToBuy minimum token to buy
     * @param _stages array of stages detail
     * @param _oracle Oracle contract to fetch ETH/USD price
     * @param _paymentWallet address to recive payments
     * @param _signer signer to validate signature
     */
    function initialize(
        uint256 _minTokenToBuy,
        uint256[][4] memory _stages,
        address _oracle,
        address _paymentWallet,
        address _signer
    ) external initializer {
        require(_oracle != address(0), "Zero aggregator address");
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        minTokenToBuy = _minTokenToBuy;
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

    /**
     * @dev To pause the sale
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev To unpause the sale
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev To calculate the price in USD for given amount of tokens.
     * @param _amount No of tokens
     * @param _sale No of sale
     */
    function calculatePrice(
        uint256 _amount,
        uint256 _sale
    ) public view returns (uint256) {
        uint256 price = _amount * stages[_sale][3];
        return price;
    }

    /**
     * @dev To buy token in a private sale using ETH
     * @param amount No of tokens to buy
     * @param sig Signature to validate user
     */
    function privateSale1TokenBuy(
        uint256 amount,
        bytes calldata sig
    )
        external
        payable
        checkSaleState(amount, uint8(saleStage.privateSale1))
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(saleStages == saleStage.privateSale1, "Sale not active");
        require(amount >= minTokenToBuy, "Less amount");

        address sigRecover = keccak256(
            abi.encodePacked(_msgSender(), amount, nonces[_msgSender()])
        ).toEthSignedMessageHash().recover(sig);
        require(sigRecover == signer, "Invalid signer");

        privateSale1TotalSold += amount;
        require(
            privateSale1TotalSold <= stages[0][2],
            "Amount exceeds max token to buy"
        );

        uint256 usdPrice = calculatePrice(
            amount,
            uint8(saleStage.privateSale1)
        );

        uint256 ethAmount = (usdPrice * baseDecimals) / getLatestPrice();
        require(msg.value >= ethAmount, "Less payment");
        uint256 excess = msg.value - ethAmount;

        nonces[_msgSender()]++;
        privateSale1Deposits[_msgSender()] += (amount * baseDecimals);
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
     * @dev To buy token in a private sale using ETH
     * @param amount No of tokens to buy
     * @param sig Signature to validate user
     */
    function privateSale2TokenBuy(
        uint256 amount,
        bytes calldata sig
    )
        external
        payable
        checkSaleState(amount, uint8(saleStage.privateSale2))
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(saleStages == saleStage.privateSale2, "Sale not active");
        require(amount >= minTokenToBuy, "Less amount");

        address sigRecover = keccak256(
            abi.encodePacked(_msgSender(), amount, nonces[_msgSender()])
        ).toEthSignedMessageHash().recover(sig);
        require(sigRecover == signer, "Invalid signer");

        privateSale2TotalSold += amount;
        require(
            privateSale2TotalSold <= stages[1][2],
            "Amount exceeds max token to buy"
        );

        uint256 usdPrice = calculatePrice(
            amount,
            uint8(saleStage.privateSale2)
        );
        uint256 ethAmount = (usdPrice * baseDecimals) / getLatestPrice();
        require(msg.value >= ethAmount, "Less payment");
        uint256 excess = msg.value - ethAmount;

        nonces[_msgSender()]++;
        privateSale2Deposits[_msgSender()] += (amount * baseDecimals);
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
     * @dev To buy token in a presale using ETH
     * @param amount No of tokens to buy
     * @param referrer Referrer address of user
     * @param sig Signature to validate user
     */
    function preSaleTokenBuy(
        uint256 amount,
        address referrer,
        bytes calldata sig
    )
        external
        payable
        checkSaleState(amount, uint8(saleStage.preSale))
        whenNotPaused
        nonReentrant
        returns (bool)
    {   
        require(referrer != _msgSender(), "Referrer set to itself");
        require(saleStages == saleStage.preSale, "Sale not active");
        require(amount >= minTokenToBuy, "Less amount");

        address sigRecover = keccak256(
            abi.encodePacked(_msgSender(), amount, nonces[_msgSender()])
        ).toEthSignedMessageHash().recover(sig);
        require(sigRecover == signer, "Invalid signer");

        preSaleTotalSold += amount;
        require(
            preSaleTotalSold <= stages[2][2],
            "Amount exceeds max token to buy"
        );

        uint256 usdPrice = calculatePrice(
            amount,
            uint8(saleStage.preSale)
        );
        uint256 ethAmount = (usdPrice * baseDecimals) / getLatestPrice();
        require(msg.value >= ethAmount, "Less payment");
        uint256 excess = msg.value - ethAmount;

        if(referrer != address(0)) {
            userRef[_msgSender()] = referrer;
        }
        nonces[_msgSender()]++;
        preSaleDeposits[_msgSender()] += (amount * baseDecimals);
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
     * @dev To buy token in a public sale using ETH
     * @param amount No of tokens to buy
     * @param referrer Referrer address of user
     * @param sig Signature to validate user
     */
    function publicSaleTokenBuy(
        uint256 amount,
        address referrer,
        bytes calldata sig
    )
        external
        payable
        checkSaleState(amount, uint8(saleStage.publicSale))
        whenNotPaused
        nonReentrant
        returns (bool)
    {   
        require(referrer != _msgSender(), "Referrer set to itself");
        require(saleStages == saleStage.publicSale, "Sale not active");
        require(amount >= minTokenToBuy, "Less amount");

        address sigRecover = keccak256(
            abi.encodePacked(_msgSender(), amount, nonces[_msgSender()])
        ).toEthSignedMessageHash().recover(sig);
        require(sigRecover == signer, "Invalid signer");

        publicSaleTotalSold += amount;
        require(
            publicSaleTotalSold <= stages[3][2],
            "Amount exceeds max token to buy"
        );

        uint256 usdPrice = calculatePrice(
            amount,
            uint8(saleStage.publicSale)
        );
        uint256 ethAmount = (usdPrice * baseDecimals) / getLatestPrice();
        require(msg.value >= ethAmount, "Less payment");
        uint256 excess = msg.value - ethAmount;

        if(referrer != address(0)) {
            userRef[_msgSender()] = referrer;
        }
        nonces[_msgSender()]++;
        publicSaleDeposits[_msgSender()] += (amount * baseDecimals);
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
     * @dev Internal function to send excess amount
     */
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
     * @param sale No of sale
     */
    function ethBuyHelper(
        uint256 amount,
        uint256 sale
    ) external view returns (uint256 ethAmount) {
        uint256 usdPrice = calculatePrice(amount, sale);
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
     * @dev To set minimum token to buy
     * @param _minAmount minimum amount
     */
    function setMinTokenToBuy(uint256 _minAmount) external onlyOwner {
        minTokenToBuy = _minAmount;
    }

    /**
     * @dev To set sale stages data
     * @param _stages sale stages data
     */
    function changeStagesData(uint256[][4] memory _stages) external onlyOwner {
        stages = _stages;
    }

    /**
     * @dev To set specific stage data
     * @param _index array index
     * @param _stage sale stage data
     */
    function changeStageData(
        uint256 _index,
        uint256[4] memory _stage
    ) external onlyOwner {
        stages[_index] = _stage;
    }

    /**
     * @dev To change signer wallet address
     * @param _signer new signer wallet address
     */
    function setSignerWallet(address _signer) external onlyOwner {
        signer = _signer;
    }
}
