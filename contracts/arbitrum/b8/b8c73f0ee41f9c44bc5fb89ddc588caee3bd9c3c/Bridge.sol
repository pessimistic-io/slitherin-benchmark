//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract Bridge is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    uint256 feeForAdminGas;
    uint24 public feeForAdmin;
    uint24 public feeForLPProvider;    
    uint256[] public chains;
    address[] public tokens;     
    mapping(address=>string) public logos;
    mapping(address => uint256) public isTokenListed;
    mapping(uint256 => uint256) public isChainListed;   
    mapping(address=>mapping(uint256=>address)) public tokensInOtherChains;
    mapping(address=>uint256) public totalBalance;
    mapping(address=>uint256) public totalLPBalance;
    mapping(address=>mapping(address=>uint256)) public LPBalanceOf;
    mapping(address=>uint256) public feeCollectedForAdmin;
    mapping(address=>uint256) public bridgeNonce;
    mapping(address=>mapping(uint256=>bool)) public nonceProcessed;

    event FeeUpdated(uint256 feeForAdminGas, uint24 feeForAdmin, uint24 feeForLPProvider);
    event AddLiquidity(address LPProvider, address token, uint256 amount, uint256 totalBalance, uint256 totalLPBalance, uint256 LPBalanceOf);
    event LiquidityRequired(address LPProvider, address[] tokens, uint256[] chains, uint256 amount);
    event RemoveLiquidity(address LPProvider, address token, uint256 amount, uint256 totalBalance, uint256 totalLPBalance, uint256 LPBalanceOf);
    event WithdrawLiquidity(address owner, address rootToken, uint256 amount, uint256 rootChain);
    event LiquidityRequiredInOtherChain(address owner, address[] tokens, uint256[] chains, uint256 amount, uint256 originChain);
    event BridgeIn(address sender, address token, uint256 chain, address to, uint256 amount, uint256 bridgeNonce);
    event BridgeOut(address sender, address to, address token, uint256 rootChain, uint256 amount);
    event BridgeReverted(address sender, address to, address token, uint256 rootChain, uint256 amount);
    event LiquidityRequiredForAdmin(address[] tokens, uint256[] chains, uint256 amount);
    event WithdrawAdminFeeInOtherChain(address token, uint256 amount, uint256 rootChain);
    event LiquidityRequiredForAdminInOtherChain(address[] tokens, uint256[] chains, uint256 amount, uint256 rootChain);

    function initialize(
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
    }

    function addChain(uint256 _chain) onlyOwner external {
        require(isChainListed[_chain]==0, "already existed");
        chains.push(_chain);
        isChainListed[_chain] = chains.length;
    }

    function removeChain(uint256 _chain) onlyOwner external {
        require(isChainListed[_chain]>0, "not existed");
        chains[isChainListed[_chain]-1] = chains[chains.length-1];
        isChainListed[chains[chains.length-1]] = isChainListed[_chain];
        delete isChainListed[_chain];
        chains.pop();      
    }

    function updateFee(uint256 _feeForAdminGas, uint24 _feeForAdmin, uint24 _feeForLPProvider) onlyOwner external {
        feeForAdminGas = _feeForAdminGas;
        feeForAdmin = _feeForAdmin;
        feeForLPProvider = _feeForLPProvider;
        emit FeeUpdated(feeForAdminGas, feeForAdmin, feeForLPProvider);
    }
    
    function addToken(address _token, string memory _logo) onlyOwner external {
        require(isTokenListed[_token]==0, "already existed");
        tokens.push(_token);
        logos[_token]=_logo;
        isTokenListed[_token] = tokens.length;
    }
    function removeToken(address _token) onlyOwner external {
        require(isTokenListed[_token]>0, "not existed");
        tokens[isTokenListed[_token]-1] = tokens[tokens.length-1];
        isTokenListed[tokens[tokens.length-1]] = isTokenListed[_token];
        delete isTokenListed[_token];
        delete logos[_token];
        tokens.pop(); 
        for(uint256 i=0;i<chains.length;i++){
            delete tokensInOtherChains[_token][chains[i]];
        }         
    }

    function setTokenForOtherChain(address _token, uint256 _chain, address _tokenForOtherChain) onlyOwner external {
        require(isTokenListed[_token]>0, "not existed");
        tokensInOtherChains[_token][_chain] = _tokenForOtherChain;
    }

    function addLiquidity(address _token, uint256 amount) external {
        require(isTokenListed[_token]>0, "not existed");
        IERC20Upgradeable(_token).safeTransferFrom(_msgSender(), address(this), amount);
        uint256 LPBalance = totalBalance[_token] > 0 ? amount * totalLPBalance[_token] / totalBalance[_token] : amount;
        totalBalance[_token] += amount;
        totalLPBalance[_token] += LPBalance;
        LPBalanceOf[_token][_msgSender()] += LPBalance;
        emit AddLiquidity(_msgSender(), _token, amount, totalBalance[_token], totalLPBalance[_token], LPBalanceOf[_token][_msgSender()]);
    }

    function removeLiquidity(address _token, uint256 amount, uint256[] memory chainsListIfInsufficient) external nonReentrant {
        require(isTokenListed[_token]>0, "not existed");
        uint256 LPBalance = totalBalance[_token] > 0 ? amount * totalLPBalance[_token] / totalBalance[_token] : amount;
        require(totalLPBalance[_token] >= LPBalance, "insufficient liquidity");
        require(LPBalanceOf[_token][_msgSender()] >= LPBalance, "You don't have enogh Liquidity");
        require(totalBalance[_token] >= amount, "insufficient token");
        if(IERC20Upgradeable(_token).balanceOf(address(this))>=amount){
            IERC20Upgradeable(_token).safeTransfer(_msgSender(), amount);
            totalLPBalance[_token] -= LPBalance;
            LPBalanceOf[_token][_msgSender()] -= LPBalance;
            totalBalance[_token] -= amount;
            emit RemoveLiquidity(_msgSender(), _token, amount, totalBalance[_token], totalLPBalance[_token], LPBalanceOf[_token][_msgSender()]);
        }else{
            uint256 _amount = IERC20Upgradeable(_token).balanceOf(address(this));
            if(_amount > 0){
                LPBalance = totalBalance[_token] > 0 ? _amount * totalLPBalance[_token] / totalBalance[_token] : _amount;
                IERC20Upgradeable(_token).safeTransfer(_msgSender(), _amount);
                totalLPBalance[_token] -= LPBalance;
                LPBalanceOf[_token][_msgSender()] -= LPBalance;
                totalBalance[_token] -= _amount;
                emit RemoveLiquidity(_msgSender(), _token, _amount, totalBalance[_token], totalLPBalance[_token], LPBalanceOf[_token][_msgSender()]);
            }        
            address[] memory _tokens;
            uint256[] memory _chains;
            uint256 count=0;
            for(uint256 i=0;i<chainsListIfInsufficient.length;i++){
                if(tokensInOtherChains[_token][chainsListIfInsufficient[i]] != address(0)){
                    _tokens[count]=tokensInOtherChains[_token][chainsListIfInsufficient[i]];
                    _chains[count]=chainsListIfInsufficient[i];
                    count++;
                }
                
            }    
            emit LiquidityRequired(_msgSender(), _tokens, _chains, amount-_amount);
        }        
    }
    function withdrawLiquidity(address owner, address _token, uint256 amount, uint256 rootChain) external onlyOwner nonReentrant {
        require(isTokenListed[_token]>0, "not existed");
        if(IERC20Upgradeable(_token).balanceOf(address(this))>=amount){
            IERC20Upgradeable(_token).safeTransfer(owner, amount);            
            emit WithdrawLiquidity(owner, tokensInOtherChains[_token][rootChain], amount, rootChain);
        }else{
            uint256 _amount = IERC20Upgradeable(_token).balanceOf(address(this));
            if(_amount > 0){
                IERC20Upgradeable(_token).safeTransfer(owner, _amount);
                emit WithdrawLiquidity(owner, tokensInOtherChains[_token][rootChain], _amount, rootChain);
            }        
            address[] memory _tokens;
            uint256[] memory _chains;
            uint256 count=0;
            for(uint256 i=0;i<chains.length;i++){
                if(tokensInOtherChains[_token][chains[i]] != address(0)){
                    _tokens[count]=tokensInOtherChains[_token][chains[i]];
                    _chains[count]=chains[i];
                }
                
            }    
            emit LiquidityRequiredInOtherChain(owner, _tokens, _chains, amount-_amount, rootChain);
        } 
    }

    function forceRemoveLiquidity(address owner, address _token, uint256 amount) external onlyOwner nonReentrant {
        require(isTokenListed[_token]>0, "not existed");
        uint256 LPBalance = totalBalance[_token] > 0 ? amount * totalLPBalance[_token] / totalBalance[_token] : amount;
        require(totalLPBalance[_token] >= LPBalance, "insufficient liquidity");
        require(LPBalanceOf[_token][owner] >= LPBalance, "You don't have enogh Liquidity");
        require(totalBalance[_token] >= amount, "insufficient token");
        totalLPBalance[_token] -= LPBalance;
        LPBalanceOf[_token][owner] -= LPBalance;
        totalBalance[_token] -= amount;
        emit RemoveLiquidity(owner, _token, amount, totalBalance[_token], totalLPBalance[_token], LPBalanceOf[_token][owner]);   
    }

    function bridgeIn(address _token, uint256 _chain, address to, uint256 amount) external payable {
        require(msg.value >= feeForAdminGas, "Insufficient fee");        
        (bool sent, ) = payable(owner()).call{value: msg.value}("");
        require(sent, "Failed to send Ether");
        require(isTokenListed[_token]>0, "not existed");
        require(tokensInOtherChains[_token][_chain]!=address(0), "no token registered");
        IERC20Upgradeable(_token).safeTransferFrom(_msgSender(), address(this), amount);
        bridgeNonce[_token] += 1;
        emit BridgeIn(_msgSender(), tokensInOtherChains[_token][_chain], _chain, to, amount, bridgeNonce[_token]);
    }

    function bridgeOut(address _token, uint256 rootChain, address sender, address to, uint256 amount, uint256 _bridgeNonce) external onlyOwner nonReentrant{
        require(isTokenListed[_token]>0, "not existed");
        require(!nonceProcessed[_token][_bridgeNonce], "already bridged!");
        nonceProcessed[_token][_bridgeNonce] = true;
        uint256 amountForAdmin = amount * feeForAdmin / 1000000;
        uint256 amountForLPProvider = amount * feeForLPProvider / 1000000;
        
        amount = amount - amountForAdmin - amountForLPProvider;
        if(IERC20Upgradeable(_token).balanceOf(address(this)) >= amount){
            feeCollectedForAdmin[_token] += amountForAdmin;
            totalBalance[_token] += amountForLPProvider;
            IERC20Upgradeable(_token).safeTransfer(to, amount);
            emit BridgeOut(sender, to, _token, rootChain, amount);
        }else{
            uint256 _amount = IERC20Upgradeable(_token).balanceOf(address(this));
            amountForAdmin = _amount * feeForAdmin / (1000000 - feeForAdmin - feeForLPProvider);
            amountForLPProvider = _amount * feeForLPProvider / (1000000 - feeForAdmin - feeForLPProvider);
            feeCollectedForAdmin[_token] += amountForAdmin;
            totalBalance[_token] += amountForLPProvider;
            if(_amount > 0){
                IERC20Upgradeable(_token).safeTransfer(to, _amount);
                emit BridgeOut(sender, to, _token, rootChain, _amount);
            }        
            
            emit BridgeReverted(sender, to, tokensInOtherChains[_token][rootChain], rootChain, (amount-_amount) * 1000000 / (1000000 - feeForAdmin - feeForLPProvider));
        }        
    }

    function bridgeRevert(address sender, address _token, uint256 amount) external onlyOwner nonReentrant{
        require(isTokenListed[_token]>0, "not existed");
        IERC20Upgradeable(_token).safeTransfer(sender, amount);
    }

    function withdrawAdminFee(address _token, uint256[] memory chainsListIfInsufficient) external onlyOwner {
        require(isTokenListed[_token]>0, "not existed");
        if(feeCollectedForAdmin[_token] <= IERC20Upgradeable(_token).balanceOf(address(this))){
            IERC20Upgradeable(_token).safeTransfer(owner(), feeCollectedForAdmin[_token]);
            feeCollectedForAdmin[_token] = 0;
        }else{
            feeCollectedForAdmin[_token] -= IERC20Upgradeable(_token).balanceOf(address(this));
            IERC20Upgradeable(_token).safeTransfer(owner(), IERC20Upgradeable(_token).balanceOf(address(this)));
            address[] memory _tokens;
            uint256[] memory _chains;
            uint256 count=0;
            for(uint256 i=0;i<chainsListIfInsufficient.length;i++){
                if(tokensInOtherChains[_token][chainsListIfInsufficient[i]] != address(0)){
                    _tokens[count]=tokensInOtherChains[_token][chainsListIfInsufficient[i]];
                    _chains[count]=chainsListIfInsufficient[i];
                    count++;
                }
                
            }    
            emit LiquidityRequiredForAdmin(_tokens, _chains, feeCollectedForAdmin[_token]);
        }

    }

    function withdrawAdminFeeInOtherChain(address _token, uint256 amount, uint256 rootChain) external onlyOwner {
        require(isTokenListed[_token]>0, "not existed");
        if(amount <= IERC20Upgradeable(_token).balanceOf(address(this))){
            IERC20Upgradeable(_token).safeTransfer(owner(), amount);
            emit WithdrawAdminFeeInOtherChain(tokensInOtherChains[_token][rootChain], amount, rootChain);
        }else{
            amount -= IERC20Upgradeable(_token).balanceOf(address(this));
            emit WithdrawAdminFeeInOtherChain(tokensInOtherChains[_token][rootChain], IERC20Upgradeable(_token).balanceOf(address(this)), rootChain);
            IERC20Upgradeable(_token).safeTransfer(owner(), IERC20Upgradeable(_token).balanceOf(address(this)));
            address[] memory _tokens;
            uint256[] memory _chains;
            uint256 count=0;
            for(uint256 i=0;i<chains.length;i++){
                if(tokensInOtherChains[_token][chains[i]] != address(0)){
                    _tokens[count]=tokensInOtherChains[_token][chains[i]];
                    _chains[count]=chains[i];
                }
                
            }    
            emit LiquidityRequiredForAdminInOtherChain(_tokens, _chains, amount, rootChain);
        }        
    }

    function forceWithdrawAdminFee(address _token, uint256 amount) external onlyOwner{
        require(isTokenListed[_token]>0, "not existed");
        feeCollectedForAdmin[_token] -= amount;
    }

    function balanceOf(address LPProvider, address _token) external view returns(uint256 amount){
        amount = totalLPBalance[_token]>0 ? LPBalanceOf[_token][LPProvider] * totalBalance[_token] / totalLPBalance[_token] : LPBalanceOf[_token][LPProvider];
    }

    function getChainsAndTokens() external view returns(uint256[] memory _chains, address[] memory _tokens, string[] memory _logos){
        _chains = chains;
        _tokens = tokens;
        for(uint256 i=0;i<tokens.length;i++){
            _logos[i] = logos[tokens[i]];
        }
    }

    function getFee() external view returns(uint256 _feeForAdminGas, uint24 _feeForAdmin, uint24 _feeForLPProvider){
        _feeForAdminGas = feeForAdminGas;
        _feeForAdmin = feeForAdmin;
        _feeForLPProvider = feeForLPProvider;
    }

}
