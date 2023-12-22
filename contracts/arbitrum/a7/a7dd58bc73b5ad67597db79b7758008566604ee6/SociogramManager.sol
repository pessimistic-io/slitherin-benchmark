// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./ECDSA.sol";
import "./SociogramMemberToken.sol";
import "./ISociogramMemberToken.sol";


/**
 * @title SociogramManager
 * @dev This contract manages the issuance, buying, and selling of Sociogram member tokens.
 */
contract SociogramManager is Initializable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using ECDSA for bytes32;

    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    address public server;
    address public teamRewardTreasury;
    uint256 public teamRewardFeePercent;
    uint256 public issuerFeePercent;

    string public constant ISSUED_TOKEN_SYMBOL = "SG";
    uint256 public constant FEE_BASE = 1000;
    IERC20 public constant BASE_TOKEN = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);// arbitrum USDT address

    mapping(bytes32 => bool) public executed;
    mapping(address => address) public issuedTokensMap;// accountId <<==>> issuedToken
    mapping(uint256 => address) public issuedTokens;
    uint256 public issuedTokensCount;

    event BuyToken(
        address indexed token, 
        uint256 tokenAmount,
        uint256 tokenCost,
        uint256 teamRewardFee, 
        uint256 issuerFee,
        uint256 totalSupply
    );
    event SellToken( 
        address indexed token, 
        uint256 tokenAmount,
        uint256 tokenCost,
        uint256 teamRewardFee, 
        uint256 issuerFee,
        uint256 totalSupply
    );
    event TokenIssued(
        address indexed tokenAddress,
        string tokenName,
        string tokenSymbol
    );

    /**
     * @dev Modifier to ensure that a transaction is executed before its deadline.
     * @param deadline The timestamp until which the transaction is valid.
     */
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "SociogramManager: EXPIRED");
        _;
    }

    /**
     * @dev Pauses the contract functions that not affect user funds.
     */
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE){
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE){
        _unpause();
    }

    /**
     * @dev Sets the server address.
     * @param _newServerAddress The new server address.
     */
    function setServer(address _newServerAddress) public onlyRole(DEFAULT_ADMIN_ROLE){
        server = _newServerAddress;
        require(server != address(0), "SociogramManager: address cannot be zero");
    }

    /**
     * @dev Sets the team reward treasury address.
     * @param _treasuryAddress The new team reward treasury address.
     */
    function setTeamRewardTreasury(address _treasuryAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        teamRewardTreasury = _treasuryAddress;
        require(teamRewardTreasury != address(0), "SociogramManager: address cannot be zero");
    }

    /**
     * @dev Sets the team reward fee percentage.
     * @param _newPercent The new team reward fee percentage.
     */
    function setTeamRewardFeePercent(uint256 _newPercent) public onlyRole(TIMELOCK_ROLE) {
        teamRewardFeePercent = _newPercent;
        require(teamRewardFeePercent <= FEE_BASE / 4, "SociogramManager: new team reward fee percent 25% or more");
    }

    /**
     * @dev Sets the issuer fee percentage.
     * @param _newPercent The new issuer fee percentage.
     */
    function setIssuerFeePercent(uint256 _newPercent) public onlyRole(TIMELOCK_ROLE) {
        issuerFeePercent = _newPercent;
        require(issuerFeePercent <= FEE_BASE / 4, "SociogramManager: new issuer fee percent 25% or more");
    }

    /**
     * @dev Initializes the contract with initial values. Used in scope of TransparentProxy Pattern
     * @param _timelockAddress The address of the timelock contract.
     * @param _server The server address.
     * @param _teamRewardTreasury The team reward treasury address.
     * @param _teamRewardFeePercent The team reward fee percentage.
     * @param _issuerFeePercent The issuer fee percentage.
     */
    function initialize(
        address _timelockAddress,
        address _server,
        address _teamRewardTreasury,
        uint256 _teamRewardFeePercent,
        uint256 _issuerFeePercent
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        server = _server;
        teamRewardTreasury = _teamRewardTreasury;
        teamRewardFeePercent = _teamRewardFeePercent;
        issuerFeePercent = _issuerFeePercent;

        require(server != address(0), "SociogramManager: address cannot be zero");
        require(teamRewardTreasury != address(0), "SociogramManager: address cannot be zero");
        require(teamRewardFeePercent <= FEE_BASE / 4, "SociogramManager: new team reward fee percent 25% or more");
        require(issuerFeePercent <= FEE_BASE / 4, "SociogramManager: new issuer fee percent 25% or more");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(TIMELOCK_ROLE, _timelockAddress);
        pause();
    }

    /**
     * @dev Calculates the price for a given supply and amount of tokens.
     * @param supply The total supply of tokens.
     * @param amount The amount of tokens being bought.
     * @return The calculated price.
     */
    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 shift = 100 ether;
        uint256 rawPrice = (supply + shift + amount)**3 - (supply + shift)**3;
        return rawPrice / 4096e51;
    }

    /**
     * @dev Gets the buy price for a given SG token and amount.
     * @param _token The address of the token.
     * @param _amount The amount of tokens being bought.
     * @return The buy price in base token.
     */
    function getBuyPrice(address _token, uint256 _amount) public view returns (uint256) {
        uint256 supply = ISociogramMemberToken(_token).totalSupply();
        uint256 cap = ISociogramMemberToken(_token).cap();
        require(supply + _amount <= cap, "SociogramManager: cant buy over cap");
        require(_amount > 0, "SociogramManager: cant buy 0 tokens");
        return getPrice(ISociogramMemberToken(_token).totalSupply(), _amount);
    }

    /**
     * @dev Gets the sell price for a given SG token and amount.
     * @param _token The address of the token.
     * @param _amount The amount of tokens being sold.
     * @return The sell price in base token.
     */
    function getSellPrice(address _token, uint256 _amount) public view returns (uint256) {
        uint256 supply = ISociogramMemberToken(_token).totalSupply();
        require(_amount > 0, "SociogramManager: cant sell 0 tokens");
        require(supply >= _amount, "SociogramManager: amount must be >= than supply");
        return getPrice(supply - _amount, _amount) - 1;
    }

    /**
     * @dev Gets the buy price for a given token and amount, including fees.
     * @param _token The address of the token.
     * @param _amount The amount of tokens being bought.
     * @return The total price, team reward fee, issuer fee, and token price.
     */
    function getBuyPriceAfterFee(address _token, uint256 _amount) external view returns (uint256, uint256, uint256, uint256) {
        uint256 price = getBuyPrice(_token, _amount);
        uint256 teamRewardFee = price * teamRewardFeePercent / FEE_BASE;
        uint256 issuerFee = price * issuerFeePercent / FEE_BASE;
        return (price + teamRewardFee + issuerFee, teamRewardFee, issuerFee, price);
    }

    /**
     * @dev Gets the sell price for a given token and amount, including fees.
     * @param _token The address of the token.
     * @param _amount The amount of tokens being sold.
     * @return The total sell price, team reward fee, issuer fee, and token price.
     */
    function getSellPriceAfterFee(address _token, uint256 _amount) external view returns (uint256, uint256, uint256, uint256) {
        uint256 price = getSellPrice(_token, _amount);
        uint256 teamRewardFee = price * teamRewardFeePercent / FEE_BASE;
        uint256 issuerFee = price * issuerFeePercent / FEE_BASE;
        return (price - teamRewardFee - issuerFee, teamRewardFee, issuerFee, price);
    }

    /**
     * @dev Issues a new Sociogram member token to the caller.
     * @param _signature The signature for verification.
     * @param _twitterId The Twitter ID of the user.
     * @param _prepurchaseAmount The initial token amount to purchase for the caller.
     * @param _maximumPayed The maximum payment allowed for this purchase.
     * @param _expirationTimestamp The expiration timestamp for the transaction.
     */
    function issueToken(
        bytes calldata _signature,
        string calldata _twitterId,
        uint256 _prepurchaseAmount,
        uint256 _maximumPayed,
        uint256 _expirationTimestamp
    ) external whenNotPaused ensure(_expirationTimestamp){
        bytes32 msgHash = keccak256(abi.encode(
            msg.sender, 
            _twitterId, 
            _expirationTimestamp
        ));
        require(!executed[msgHash], "SociogramManager: has been executed!");
        require(msgHash.toEthSignedMessageHash().recover(_signature) == server, "SociogramManager: bad signature");
        require(issuedTokensMap[msg.sender] == address(0), "SociogramManager: user already have issued token");
        executed[msgHash] = true;

        //add hooks before after transfer
        address tokenContractAddress = address(new SociogramMemberToken(msg.sender, _twitterId, ISSUED_TOKEN_SYMBOL));
        issuedTokens[issuedTokensCount++] = tokenContractAddress;
        issuedTokensMap[msg.sender] = tokenContractAddress;
        issuedTokensMap[tokenContractAddress] = msg.sender;

        emit TokenIssued(
            tokenContractAddress,
            _twitterId,
            ISSUED_TOKEN_SYMBOL 
        ); 

        if (_prepurchaseAmount > 0){
            uint256 userPayment = _buyTokens(tokenContractAddress, _prepurchaseAmount);
            require(userPayment <= _maximumPayed, "SociogramManager: maximal payment for this purchase exceeded");
        }
    }

    /**
     * @dev Buys already issued SG member token (increasing supply)
     * @param _token The address of the token contract.
     * @param _amount The amount of tokens to buy.
     * @param _maximumPayed The maximum payment allowed for this purchase.
     * @param _deadline The deadline for the transaction.
     */
    function buyTokens(
        address _token, 
        uint256 _amount, 
        uint256 _maximumPayed, 
        uint256 _deadline
    ) public whenNotPaused nonReentrant ensure(_deadline){
        uint256 userPayment = _buyTokens(_token, _amount);  
        require(userPayment <= _maximumPayed, "SociogramManager: maximal payment for this purchase exceeded");
    }

    function _buyTokens(address _token, uint256 _amount) internal returns(uint256 userPayment){
        require(issuedTokensMap[_token] != address(0), "SociogramManager: token not issued by Sociogram member");
        uint256 price = getBuyPrice(_token, _amount);
        require(price >= FEE_BASE, "SociogramManager: min notional");

        uint256 teamRewardFee = price * teamRewardFeePercent / FEE_BASE;
        uint256 issuerFee = price * issuerFeePercent / FEE_BASE;
        userPayment = price + teamRewardFee + issuerFee;

        BASE_TOKEN.transferFrom(msg.sender, address(this), userPayment);
        BASE_TOKEN.transfer(teamRewardTreasury, teamRewardFee);
        BASE_TOKEN.transfer(_token, issuerFee);
        ISociogramMemberToken(_token).mint(msg.sender, _amount);

        emit BuyToken( 
            _token, 
            _amount, 
            price,
            teamRewardFee, 
            issuerFee,
            ISociogramMemberToken(_token).totalSupply()
        );
    }   

    /**
     * @dev Sells issued SG member token (reducing supply)
     * @param _token The address of the token contract.
     * @param _amount The amount of tokens to sell.
     * @param _minimumReceived The minimum amount to receive for this sale.
     * @param _deadline The deadline for the transaction.
     */
    function sellTokens(
        address _token, 
        uint256 _amount, 
        uint256 _minimumReceived, 
        uint256 _deadline
    ) public whenNotPaused nonReentrant ensure(_deadline){
        uint256 userReceive = _sellTokens(_token, _amount);
        require(userReceive >= _minimumReceived, "SociogramManager: the minimum revenue for this sale has not been reached");
    }

    function _sellTokens(address _token, uint256 _amount) internal returns(uint256 userReceive){
        require(issuedTokensMap[_token] != address(0), "SociogramManager: token not issued by Sociogram member");
        uint256 price = getSellPrice(_token, _amount);
        require(price >= FEE_BASE, "SociogramManager: min notional");
        uint256 teamRewardFee = price * teamRewardFeePercent / FEE_BASE;
        uint256 issuerFee = price * issuerFeePercent / FEE_BASE;
        userReceive = price - teamRewardFee - issuerFee;
        
        BASE_TOKEN.transfer(msg.sender, userReceive);
        BASE_TOKEN.transfer(teamRewardTreasury, teamRewardFee);
        BASE_TOKEN.transfer(_token, issuerFee);
        ISociogramMemberToken(_token).burnFrom(msg.sender, _amount);

        emit SellToken(
            _token, 
            _amount, 
            price,
            teamRewardFee, 
            issuerFee,
            ISociogramMemberToken(_token).totalSupply()
        );
    }
    
}
