// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ArcBase} from "./ArcBase.sol";
import {IArc} from "./IArc.sol";
import {IRainbowRoad} from "./IRainbowRoad.sol";
import {IHandler} from "./IHandler.sol";

/**
 * Manages sending and receiving of tokens and NFTs between chains
 */
contract RainbowRoad is ArcBase, IRainbowRoad
{
    IArc public arc;
    address public team;
    address public pendingTeam;
    uint256 public constant MAX_TEAM_RATE = 750; // 75%
    uint256 public teamRate;
    uint256 public sendFee;
    uint256 public whitelistingFee;
    bool public chargeSendFee;
    bool public chargeWhitelistingFee;
    bool public burnSendFee;
    bool public burnWhitelistingFee;
    bool public openTokenWhitelisting;
    mapping(address => bool) public feeManagers;
    mapping(address => bool) public receivers;
    mapping(address => bool) public senders;
    mapping(address => bool) public blockedTokens;
    mapping(string => address) public tokens;
    mapping(string => address) public actionHandlers;
    mapping(string => bytes) public config;
    
    constructor(address _arc)
    {
        require(_arc != address(0), 'Arc cannot be zero address');
        arc = IArc(_arc);
        team = 0x0c5D52630c982aE81b78AB2954Ddc9EC2797bB9c;
        teamRate = 400; // 400 bps = 40%
        openTokenWhitelisting = false;
        sendFee = 100000e18;
        whitelistingFee = 1000000e18;
        chargeSendFee = true;
        chargeWhitelistingFee = true;
        burnSendFee = true;
        burnWhitelistingFee = true;
        feeManagers[msg.sender] = true;
        feeManagers[team] = true;
        feeManagers[0x726461FA6e788bd8a79986D36F1992368A3e56eA] = true;
        tokens['Arc'] = _arc;
    }
    
    function setArc(address _arc) external onlyOwner
    {
        require(_arc != address(0), 'Arc cannot be zero address');
        arc = IArc(_arc);
    }
    
    function setTeam(address _team) external onlyTeam {
        pendingTeam = _team;
    }

    function acceptTeam() external {
        require(msg.sender == pendingTeam, "Invalid pending team");
        team = pendingTeam;
    }

    function setTeamRate(uint256 _teamRate) external onlyTeam {
        require(_teamRate <= MAX_TEAM_RATE, "Team rate too high");
        teamRate = _teamRate;
    }
    
    function setSendFee(uint256 _fee) external onlyFeeManagers
    {
        require(_fee > 0, 'Fee must be greater than zero');
        sendFee = _fee;
    }
    
    function setWhitelistingFee(uint256 _fee) external onlyFeeManagers
    {
        require(_fee > 0, 'Fee must be greater than zero');
        whitelistingFee = _fee;
    }
    
    function setToken(string calldata tokenSymbol, address tokenAddress) external onlyOwner
    {
        tokens[tokenSymbol] = tokenAddress;
    }
    
    function setActionHandler(string memory action, address handler) external onlyOwner
    {
        actionHandlers[action] = handler;
    }
    
    function blockToken(address tokenAddress) external onlyOwner
    {
        require(tokenAddress != address(0), 'Token address cannot be zero address');
        require(!blockedTokens[tokenAddress], 'Token address is blocked');
        blockedTokens[tokenAddress] = true;
    }
    
    function unblockToken(address tokenAddress) external onlyOwner
    {
        require(tokenAddress != address(0), 'Token address cannot be zero address');
        require(blockedTokens[tokenAddress], 'Token address is unblocked');
        blockedTokens[tokenAddress] = false;
    }
    
    function whitelist(address tokenAddress) external
    {
        string memory tokenSymbol = IERC20Metadata(tokenAddress).symbol();
        require(openTokenWhitelisting, 'Open token whitelisting is disabled');
        require(tokenAddress != address(0), 'Token address cannot be zero address');
        require(tokens[tokenSymbol] == address(0), 'Token is already enabled');
        require(!blockedTokens[tokenAddress], 'Token address is blocked');
        
        if(chargeWhitelistingFee) {
            arc.transferFrom(msg.sender, address(this), whitelistingFee);
            
            uint256 teamFee = (teamRate * whitelistingFee) / 1000;
            require(arc.transfer(team, teamFee));
            
            if(burnWhitelistingFee) {
                arc.burn(whitelistingFee - teamFee);
            }
        }
        
        tokens[tokenSymbol] = tokenAddress;
    }
    
    function enableOpenTokenWhitelisting() external onlyOwner
    {
        require(!openTokenWhitelisting, 'Open token whitelisting is enabled');
        openTokenWhitelisting = true;
    }
    
    function disableOpenTokenWhitelisting() external onlyOwner
    {
        require(openTokenWhitelisting, 'Open token whitelisting is disabled');
        openTokenWhitelisting = false;
    }
    
    function enableSendFeeCharge() external onlyOwner
    {
        require(!chargeSendFee, 'Charge send fee is enabled');
        chargeSendFee = true;
    }
    
    function disableSendFeeCharge() external onlyOwner
    {
        require(chargeSendFee, 'Charge send fee is disabled');
        chargeSendFee = false;
    }
    
    function enableSendFeeBurn() external onlyOwner
    {
        require(!burnSendFee, 'Burn send fee is enabled');
        burnSendFee = true;
    }
    
    function disableSendFeeBurn() external onlyOwner
    {
        require(burnSendFee, 'Burn send fee is disabled');
        burnSendFee = false;
    }
    
    function enableWhitelistingFeeCharge() external onlyOwner
    {
        require(!chargeWhitelistingFee, 'Charge whitelisting fee is enabled');
        chargeWhitelistingFee = true;
    }
    
    function disableWhitelistingFeeCharge() external onlyOwner
    {
        require(chargeWhitelistingFee, 'Charge whitelisting fee is disabled');
        chargeWhitelistingFee = false;
    }
    
    function enableWhitelistingFeeBurn() external onlyOwner
    {
        require(!burnWhitelistingFee, 'Burn whitelisting fee is enabled');
        burnWhitelistingFee = true;
    }
    
    function disableWhitelistingFeeBurn() external onlyOwner
    {
        require(burnWhitelistingFee, 'Burn whitelisting fee is disabled');
        burnWhitelistingFee = false;
    }
    
    function enableFeeManager(address feeManager) external onlyOwner
    {
        require(!feeManagers[feeManager], 'Fee manager is enabled');
        feeManagers[feeManager] = true;
    }
    
    function disableFeeManager(address feeManager) external onlyOwner
    {
        require(feeManagers[feeManager], 'Fee manager is disabled');
        feeManagers[feeManager] = false;
    }
    
    function enableReceiver(address receiver) external onlyOwner
    {
        require(!receivers[receiver], 'Receiver is enabled');
        receivers[receiver] = true;
    }
    
    function disableReceiver(address receiver) external onlyOwner
    {
        require(receivers[receiver], 'Receiver is disabled');
        receivers[receiver] = false;
    }
    
    function enableSender(address sender) external onlyOwner
    {
        require(!senders[sender], 'Sender is enabled');
        senders[sender] = true;
    }
    
    function disableSender(address sender) external onlyOwner
    {
        require(senders[sender], 'Sender is disabled');
        senders[sender] = false;
    }
    
    function setConfig(string calldata configName, bytes calldata configData) external onlyOwner
    {
        config[configName] = configData;
    }
    
    function receiveAction(string calldata action, address to, bytes calldata payload) external onlyReceivers whenNotPaused nonReentrant
    {
        require(actionHandlers[action] != address(0), 'Unsupported action');
        require(to != address(0), 'To cannot be zero address');
        IHandler(actionHandlers[action]).handleReceive(to, payload);
    }
    
    function sendAction(string calldata action, address from, bytes calldata payload) external onlySenders whenNotPaused nonReentrant
    {
        require(actionHandlers[action] != address(0), 'Unsupported action');
        require(from != address(0), 'From cannot be zero address');
        
        if(chargeSendFee) {
            arc.transferFrom(from, address(this), sendFee);
            
            uint256 teamFee = (teamRate * sendFee) / 1000;
            require(arc.transfer(team, teamFee));
            
            if(burnSendFee) {
                arc.burn(sendFee - teamFee);
            }
        }
        
        IHandler(actionHandlers[action]).handleSend(from, payload);
    }
    
    receive() external payable {}
    
    /// @dev Only calls from the enabled fee managers are accepted.
    modifier onlyFeeManagers() 
    {
        require(feeManagers[msg.sender], 'Invalid fee manager');
        _;
    }
    
    /// @dev Only calls from the enabled receivers are accepted.
    modifier onlyReceivers() 
    {
        require(receivers[msg.sender], 'Invalid receiver');
        _;
    }
    
    /// @dev Only calls from the enabled senders are accepted.
    modifier onlySenders() 
    {
        require(senders[msg.sender], 'Invalid sender');
        _;
    }
    
    /// @dev Only calls from the team are accepted.
    modifier onlyTeam() 
    {
        require(msg.sender == team, "Invalid team");
        _;
    }
}

