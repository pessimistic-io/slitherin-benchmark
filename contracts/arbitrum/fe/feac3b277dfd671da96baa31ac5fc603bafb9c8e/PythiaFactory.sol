// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./AbstractMarket.sol";
import "./MarketDeployer.sol";
import "./ReputationTokenDeployer.sol";

contract PythiaFactory is ERC721, Ownable {
    using Counters for Counters.Counter;

    event PriceFeedsMarketCreated(
        address indexed _address,
        uint256 _creationTimestamp,
        string _question,
        uint256[5] _options,
        uint256 _numberOfOutcomes,
        uint256 _wageDeadline,
        uint256 _resolutionDate,
        address _reputationTokenAddress
    );

    event RealityETHMarketCreated(
        address indexed _address,
        uint256 _creationDate,
        string _question,
        uint256 _wageDeadline,
        uint256 _resolutionDate,
        address _reputationTokenAddress,
        uint256 _template
    );

    event UserCreated(
        address indexed _address,
        uint256 _registrationDate
    );

    event ReputationTokenCreated(
        address indexed _address,
        string _topic,
        string _symbol,
        uint256 _creationDate
    );

    event ReputationTransactionSent(
        address indexed _user,
        address indexed _market,
        uint256 _reputation,
        uint256 _decodedPrediction,
        uint256 _reputationCollectionDate
    );

    event PredictionCreated(
        address indexed _user,
        address indexed _market,
        bytes32 _prediction,
        uint256 _predictionDate
    );

    event MarketResolved(
        address indexed _address,
        uint256 _answer,
        uint256 _resolutionDate
    );

    // user representation
    struct User{
        uint256 registrationDate;
        bool active;
    }

    //market 
    struct Market{
        bool active;
        address reputationTokenAddress;
    }


    // reputation transaction representation
    struct ReputationTransaction{
        address user;
        address market;
        uint256 amount;
        bool received;
    }
    
    // users
    mapping(address => User) private users;

    //markets
    mapping(address => Market) private markets;

    // reputation token transactions
    mapping(uint256 => ReputationTransaction) private reputationTransactions;

    // reputation tokens
    mapping(address => bool) private reputationTokens;

    // legth of trial period
    uint256 public trialPeriod;

    Counters.Counter private _tokenIdCounter;

    constructor() ERC721("PythiaFactory", "PYAF")
    Ownable()
    {}

    /**
    * @dev create account
    */
    function createAccount() external  {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);
        User memory user = User(
            {
                registrationDate: block.timestamp,
                active: true
            }
        );
        users[msg.sender] = user;
        emit UserCreated(msg.sender, user.registrationDate);
    }
    
    /**
    * @dev check if account exists
    * @param _user Address of user
    * @return true if account exists
    */
    function isUser(address _user) external view returns(bool){
        return users[_user].active;
    }

    /**
    * @dev create PriceFeeds market
    * @param _question Question
    * @param _outcomes List of possible outcomes - prices
    * @param _numberOfOutcomes Number of outcomes
    * @param _wageDeadline Prediction Deadline for the market
    * @param _resolutionDate Resolution Date of the market
    * @param _priceFeedAddress Address of chainlink pricefeed
    * @param _priceFeederAddress Address of the pricefeeder contract
    * @param _reputationTokenAddress Address of reputation token for this market
    */
    function createPriceFeedsMarket(
        string memory _question,
        uint256[5] memory _outcomes,
        uint256 _numberOfOutcomes,
        uint256 _wageDeadline,
        uint256 _resolutionDate,
        address _priceFeedAddress,
        address _priceFeederAddress,
        address _reputationTokenAddress
    ) external onlyOwner{
        address _marketAddress = MarketDeployer.deployPriceFeedsMarket(
            address(this),
            _question,
            _outcomes,
            _numberOfOutcomes,
            _wageDeadline,
            _resolutionDate,
            _priceFeedAddress,
            _priceFeederAddress
        );
        markets[_marketAddress].active = true;
        markets[_marketAddress].reputationTokenAddress = _reputationTokenAddress;
        emit PriceFeedsMarketCreated(
            _marketAddress,
            block.timestamp,
            _question,
            _outcomes,
            _numberOfOutcomes,
            _wageDeadline,
            _resolutionDate,
            _reputationTokenAddress
        );
    }

    /**
    * @dev create Reality ETH market
    * @param _question Question
    * @param _numberOfOutcomes Number of outcomes
    * @param _wageDeadline Prediction Deadline for the market
    * @param _resolutionDate Resolution Date of the market
    * @param _arbitrator Arbitrator for RealityEth market
    * @param _timeout _timeout param for RealityEth market
    * @param _nonce _nonce param for RealityEth market
    * @param _realityEthAddress Address of RealityETH contract (chain specific)
    * @param _min_bond Min bond param reality eth market
    * @param _reputationTokenAddress Address of the Reputation Token
    */
    function createRealityEthMarket(
        string memory _question,
        uint256 _numberOfOutcomes,
        uint256 _wageDeadline,
        uint256 _resolutionDate,
        uint256 _template_id,
        address _arbitrator,
        uint32 _timeout,
        uint256 _nonce,
        address _realityEthAddress,
        uint256 _min_bond,
        address _reputationTokenAddress
    ) public onlyOwner {
        address _marketAddress = MarketDeployer.deployRealityETHMarket(
            address(this),
            _question,
            _numberOfOutcomes,
            _wageDeadline,
            _resolutionDate,
            _template_id,
            _arbitrator,
            _timeout,
            _nonce,
            _realityEthAddress,
            _min_bond
        );
        markets[_marketAddress].active = true;
        markets[_marketAddress].reputationTokenAddress = _reputationTokenAddress;
        emit RealityETHMarketCreated(
            _marketAddress,
            block.timestamp,
            _question,
             _wageDeadline,
            _resolutionDate,
            _reputationTokenAddress,
            _template_id
        );

    }

    /**
    * @dev deploys reputation token
    * @param _topic topic
    * @param _symbol symbol
    */
    function deployReputationToken(
        string memory _topic,
        string memory _symbol
    ) external {
       address _reputationTokenAddress = ReputationTokenDeployer.deploy(
            _topic,
            _symbol
       );

        emit ReputationTokenCreated(
            _reputationTokenAddress,
            _topic,
            _symbol,
            block.timestamp
        );
        // return true;
    }

    /**
    * @dev receive reputation for multiple markets
    * @param marketAdresses market address
    * @param decodedPredictions decoded predictions
    * @param signatures signatures
    */
    function receiveReputationMultipleMarkets(
        address[] calldata marketAdresses,
        uint256[] calldata decodedPredictions,
        bytes[] calldata signatures
    ) external returns(bool){
        uint256 nmarkets = marketAdresses.length;
        uint256 ndecodedPredictions = decodedPredictions.length;
        uint256 nsignatures = signatures.length;
        require(
            nmarkets == ndecodedPredictions,
            "number of predictions passed is not equal to number of marketds"
        );

        require(
            nmarkets == nsignatures,
            "number of signatures passed is not equal to number of marketds"
        );
        for(uint256 i = 0; i < nmarkets;) {
            unchecked {
                receiveReputation(
                    marketAdresses[i],
                    decodedPredictions[i],
                    signatures[i]
                );
            }
        }
        return true;
    }

    function logNewPrediction(
        address _user,
        address _market,
        bytes32 _prediction,
        uint256 _predictionTimestamp
    ) external {
        emit PredictionCreated(
            _user,
            _market,
            _prediction,
            _predictionTimestamp
        );
    }

    function logMarketResolved(
        address _market
    ) external {
        AbstractMarket market = AbstractMarket(_market);
        require(market.resolved() == true, "market is not resolved");
        emit MarketResolved(
            _market,
            market.answer(),
            block.timestamp
        );
    }

    
    function updateTrialPeriod(uint256 _newtrialPeriod) public onlyOwner{
        trialPeriod =  _newtrialPeriod;
    }


     /**
    * @dev receive reputation for the market
    * @param _marketAddress Address of the market
    * @param _decodedPrediction hash of signature of prediction
    * @param  _signature Supposed preimage of _decodedPrediction
    */
    function receiveReputation(
        address _marketAddress,
        uint256 _decodedPrediction,
        bytes calldata _signature
    ) public {
        require(markets[_marketAddress].active == true, "market with this address does not exists");
        uint256 _reputationTransactionHash = uint256(
            keccak256(
                abi.encodePacked(msg.sender, _marketAddress)
            )
        );

        require(
            reputationTransactions[_reputationTransactionHash].received == false,
            "reputation was already received"
        );

        AbstractMarket _market = AbstractMarket(_marketAddress);

        _market.verifyPrediction(_decodedPrediction, _signature);
        uint256 _reputation = _market.calculateReputation();
    
        address _reputationTokenAddress = markets[_marketAddress].reputationTokenAddress;

        ReputationToken _token = ReputationToken(
            _reputationTokenAddress
        );

        reputationTransactions[_reputationTransactionHash].user = msg.sender;
        reputationTransactions[_reputationTransactionHash].market = _marketAddress;
        reputationTransactions[_reputationTransactionHash].amount = _reputation;
        reputationTransactions[_reputationTransactionHash].received = true;

        _token.rate(msg.sender, _reputation);
        emit ReputationTransactionSent(
            msg.sender,
            _marketAddress,
            _reputation,
            _decodedPrediction,
            block.timestamp
        );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override {
        require(
            users[to].active == false,
            "user already exists"
        );
        require(
            from == address(0) || to == address(0),
            "can't transfer profile"
        );
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override {
        emit Transfer(to, from, firstTokenId);
    }

}
