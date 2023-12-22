// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./IWrapped.sol";
import "./ISparkSwapRouter02.sol";


interface IMintBurnToken {
    function mint(address to, uint256 amount) external returns (bool);
    function burn(address from, uint256 amount) external returns (bool);
}


contract BridgePulseV2 is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant DIVIDER = 10000;
    uint256 public constant MIN_AMOUNT_OUT = 0;

    struct Order {
        uint256 id;
        uint256 tokenId;
        address sender;
        address recipient;
        uint256 chainId;
        uint256 amount;
        uint256 feeAmount;
        uint256 decimals;
        address tokenIn;
        address tokenOut;
        bool payInNative;
        uint256 timestamp;
        bool closed;
    }

    struct Token {
        IERC20Metadata token;
        address feeTarget;
        uint16 defaultFee;
        uint256 defaultFeeBase;
        uint256 defaultMinAmount;
        uint256 defaultMaxAmount;
    }

    struct Config {
        IERC20Metadata tokenOnChainDestination;
        uint16 fee;
        uint256 feeBase;
        uint256 minAmount;
        uint256 maxAmount;
        bool directTransferAllowed;
    }

    struct CompleteParams {
        uint256 orderId;
        uint256 chainIdFrom;
        uint256 tokenId;
        address payable recipient;
        uint256 amount;
        uint256 decimal;
        IERC20Metadata tokenOut;
        address[] swapPath;
        bool payInNative;
        uint256 timestampFrom;
    }


    ISparkSwapRouter02 public router;
    address public wnative;

    EnumerableSet.AddressSet private _tokensMintBurnLogicList;

    mapping(address => bool) public nodeGroup;

    mapping(uint256 => Token) public tokens;
    mapping(address => uint256) public tokensToId;

    mapping(uint256 => mapping(uint256 => Config)) public bridgeTokenToChainConfig;

    mapping(uint256 => Order) public orders;

    mapping(bytes32 => bool) public completed;

    uint256 public nextTokenId = 1;
    uint256 public nextOrderId = 1;

    bool public swapsAllowed;
    uint256 public swapDefaultTokenId;


    event NodeGroupUpdated(address indexed user, bool isNodeGroup); 
    event TokenSetted(Token tokenSetted);
    event ConfigSetted(Config config);
    event OrderCreated(uint256 indexed id, Order order, uint256 feeAmount);
    event OrderCompleted(uint256 indexed id, uint indexed chainIdFrom);
    event TokensMintBurnLogicAdded(address[] tokens);
    event TokensMintBurnLogicRemoved(address[] tokens);

    modifier onlyNodeGroup {
        require(nodeGroup[msg.sender] || msg.sender == owner(), "Caller is not a node group");
        _;
    }


    constructor(address _wnative) {
        require(_wnative != address(0), "Address wnative is zero");
        wnative = _wnative;
    }


    receive() external payable {
        assert(msg.sender == wnative);
    }


    function setNodeGroup(address _user, bool _isNodeGroup) public onlyOwner {
        require(_user != address(0), "Address for NodeGroup is zero");
        nodeGroup[_user] = _isNodeGroup;
        emit NodeGroupUpdated(_user, _isNodeGroup);
    }

    function setRouter(ISparkSwapRouter02 _newRouter) external onlyOwner {
        require(address(_newRouter) != address(0), "Address for router is zero");
        router = _newRouter;
    }

    function setSwapSettings(bool _allowed, uint256 _tokenId) external onlyOwner {
        swapsAllowed = _allowed;
        swapDefaultTokenId = _tokenId;
    }

    function setPaused(bool _setPause) external onlyOwner {
        _setPause ? _pause() : _unpause();
    }


    function setToken(
        IERC20Metadata _token,
        address _feeTarget,
        uint16 _defaultFee,
        uint256 _defaultFeeBase,
        uint256 _defaultMinAmount,
        uint256 _defaultMaxAmount
    ) public onlyOwner {
        require(address(_token) != address(0), "Address for token is zero");
        require(_feeTarget != address(0), "Address for feeTarget is zero");
        require(_defaultFee <= DIVIDER, "Invalid fee");

        tokens[nextTokenId] = Token(
            _token,
            _feeTarget,
            _defaultFee,
            _defaultFeeBase,
            _defaultMinAmount,
            _defaultMaxAmount
        );
        tokensToId[address(_token)] = nextTokenId;

        emit TokenSetted(tokens[nextTokenId]);

        ++nextTokenId;
    }


    function setTokenToChainConfig(
        uint256 _tokenId,
        uint256 _chainId,
        Config calldata _config
    ) external onlyOwner {
        require(address(_config.tokenOnChainDestination) != address(0), "Address for token is zero");
        require(_config.fee <= DIVIDER, "Invalid fee");
        bridgeTokenToChainConfig[_tokenId][_chainId] = _config;

        emit ConfigSetted(_config);
    }


    function addTokensMintBurnLogicList(address[] memory _tokens) external onlyOwner returns (bool) {
        uint256 len = _tokens.length;
        for (uint256 i; i < len;) {
            _tokensMintBurnLogicList.add(_tokens[i]);
            unchecked {
                ++i;
            }
        }
        emit TokensMintBurnLogicAdded(_tokens);
        return true;
    }


    function removeTokensMintBurnLogicList(address[] memory _tokens) external onlyOwner returns (bool) {
        uint256 len = _tokens.length;
        for (uint256 i; i < len;) {
            _tokensMintBurnLogicList.remove(_tokens[i]);
            unchecked {
                ++i;
            }
        }
        emit TokensMintBurnLogicRemoved(_tokens);
        return true;
    }   


    function create(
        uint256 _tokenId,
        uint256 _amount,
        uint256 _chainId,
        address _recipient,
        bool _payInNative
    ) public payable nonReentrant whenNotPaused returns (bool) {
        Token storage tok = tokens[_tokenId];
        require(address(tok.token) != address(0), "Unknown token");

        require(
            _checkAmount(_tokenId, _chainId, _amount),
            "Amount must be in allowed range"
        );

        require(
            checkFee(_tokenId, _chainId, _amount),
            "Amount is less than fee"
        );

        if (address(tok.token) == wnative && msg.value > 0) {
            require(
                _amount == msg.value,
                "Native token amount must be equal amount parameter"
            );
            IWrapped(wnative).deposit{value: msg.value}();
        } else {
            tok.token.safeTransferFrom(msg.sender, address(this), _amount);
        }

        uint256 feeAmount = _transferFee(_tokenId, _chainId, _amount);

        if (tokensMintBurnLogicListContains(address(tok.token))) IMintBurnToken(address(tok.token)).burn(address(this), _amount - feeAmount);

        orders[nextOrderId] = Order(
            nextOrderId,
            _tokenId,
            msg.sender,
            _recipient,
            _chainId,
            _amount - feeAmount,
            feeAmount,
            _tokenDecimals(tok.token),
            address(0),
            address(0),
            _payInNative,
            block.timestamp,
            false
        );

        emit OrderCreated(nextOrderId, orders[nextOrderId], feeAmount);
        ++nextOrderId;

        return true;
    }


    function createWithSwap(
        IERC20Metadata _tokenIn,
        uint256 _amount,
        uint256 _chainId,
        address _recipient,
        address _tokenOut,
        address[] calldata _swapPath,
        bool _payInNative
    ) external payable nonReentrant whenNotPaused returns (bool) {
        require(!tokensMintBurnLogicListContains(address(_tokenIn)), "TokenIn is MintBurnLogic");
        require(
            swapsAllowed && address(router) != address(0),
            "Swaps currently disabled"
        );

        if (address(_tokenIn) == wnative && msg.value > 0) {
            require(
                _amount == msg.value,
                "Native token amount must be equal amount parameter"
            );
            IWrapped(wnative).deposit{value: msg.value}();
        } else {
            _tokenIn.safeTransferFrom(msg.sender, address(this), _amount);
        }

        uint256 tokenId = swapDefaultTokenId;
        uint256 tokenInId = tokensToId[address(_tokenIn)];
        if (
            tokens[tokenInId].token == _tokenIn &&
            bridgeTokenToChainConfig[tokenInId][_chainId].directTransferAllowed
        ) {
            tokenId = tokenInId;
        }

        Token memory tok = tokens[tokenId];

        if (tok.token != _tokenIn) {
            _tokenIn.approve(address(router), _amount);
            uint256 balanceBefore = tok.token.balanceOf(address(this));
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amount,
                MIN_AMOUNT_OUT,
                _swapPath,
                address(this),
                block.timestamp
            );
            _amount = tok.token.balanceOf(address(this)) - balanceBefore;
        }

        require(
            _checkAmount(tokenId, _chainId, _amount),
            "Amount must be in allowed range"
        );

        require(
            checkFee(tokenId, _chainId, _amount),
            "Amount is less than fee"
        );

        uint256 feeAmount = _transferFee(tokenId, _chainId, _amount);

        orders[nextOrderId] = Order(
            nextOrderId,
            tokenId,
            msg.sender,
            _recipient,
            _chainId,
            _amount - feeAmount,
            feeAmount,
            _tokenDecimals(tok.token),
            address(_tokenIn),
            _tokenOut,
            _payInNative,
            block.timestamp,
            false
        );

        emit OrderCreated(nextOrderId, orders[nextOrderId], feeAmount);
        ++nextOrderId;

        return true;
    }


    function completeOrder(
        uint256 _orderId,
        uint256 _chainIdFrom,
        uint256 _tokenId,
        address payable _recipient,
        uint256 _amount,
        uint256 _decimals,
        IERC20Metadata _tokenOut,
        address[] calldata _swapPath,
        bool _payInNative,
        uint256 _timestampFrom
    ) public onlyNodeGroup returns (uint256) {

        bytes32 orderHash = keccak256(abi.encodePacked(_orderId, _chainIdFrom, _timestampFrom));
        require(completed[orderHash] == false, "Already transfered");
        require(!Address.isContract(_recipient), "Contract targets not supported");

        Token storage tok = tokens[_tokenId];
        require(address(tok.token) != address(0), "Unknown token");
        completed[orderHash] = true;

        uint256 amount = _convertAmount(tok.token, _amount, _decimals);


        if (tokensMintBurnLogicListContains(address(tok.token))) {
            IMintBurnToken(address(tok.token)).mint(_recipient, amount);
        } else {
            if (address(_tokenOut) != address(0) && tok.token != _tokenOut) {
                tok.token.approve(address(router), amount);

                if (address(_tokenOut) == wnative && _payInNative) {

                    uint256 balanceBefore = _tokenOut.balanceOf(address(this));
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        amount,
                        MIN_AMOUNT_OUT,
                        _swapPath,
                        address(this),
                        block.timestamp
                    );
                    uint256 amountOut = _tokenOut.balanceOf(address(this)) - balanceBefore;

                    IWrapped(wnative).withdraw(amountOut);
                    (bool success,) = payable(_recipient).call{value: amountOut}("");
                    require(success, "WNative transfer failed");
    
                } else {
                    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        amount,
                        MIN_AMOUNT_OUT,
                        _swapPath,
                        _recipient,
                        block.timestamp
                    );
                }
            } else {
                if (address(tok.token) == wnative && _payInNative) {
                    IWrapped(wnative).withdraw(amount);
                    (bool success,) = payable(_recipient).call{value: amount}("");
                    require(success, "WNative transfer failed");

                } else {
                    tok.token.safeTransfer(_recipient, amount);
                }
            }
        }

        emit OrderCompleted(_orderId, _chainIdFrom);
        return amount;
    }
    

    function completeBatchOrders(
        CompleteParams[] calldata params
    ) external onlyNodeGroup {
        uint256 len = params.length;
        for (uint i; i < len;) {
            completeOrder(
                params[i].orderId,
                params[i].chainIdFrom,
                params[i].tokenId,
                params[i].recipient,
                params[i].amount,
                params[i].decimal,
                params[i].tokenOut,
                params[i].swapPath,
                params[i].payInNative,
                params[i].timestampFrom
            );
            unchecked {
                ++i;
            }
        }
    }


    function closeOrder(uint256 _orderId) external onlyNodeGroup returns (bool) {
        Order storage order_ = orders[_orderId];

        require(order_.tokenId > 0, "Order not in the list");
        require(!order_.closed, "Order closed");

        IERC20Metadata token_ = tokens[order_.tokenId].token;
        order_.closed = true;

        if (tokensMintBurnLogicListContains(address(token_))) {
            IMintBurnToken(address(token_)).mint(order_.sender, order_.amount);
        } else {
            token_.safeTransfer(order_.sender, order_.amount);
        }
        
        return true;
    }


    function withdrawToken(
        IERC20Metadata _token,
        address _to,
        uint256 _amount,
        bool _payInNative
    ) external onlyNodeGroup returns (bool) {
        if (address(_token) == wnative && _payInNative) {
            payable(_to).transfer(_amount);
        } else {
            _token.safeTransfer(_to, _amount);
        }
        return true;
    }


    function tokensMintBurnLogicListCount() external view returns (uint256) {
        return _tokensMintBurnLogicList.length();
    }

    function tokensMintBurnLogicList(uint256 index) external view returns (address) {
        return _tokensMintBurnLogicList.at(index);
    }

    function getTokenById(uint256 _tokenId) external view returns (Token memory) {
        return tokens[_tokenId];
    }

    function getTokenByAddress(address _token) external view returns (Token memory) {
        return tokens[tokensToId[_token]];
    }

    function isCompleted(
        uint256 _orderId,
        uint256 _chainIdFrom,
        uint256 _timestampFrom
    ) external view returns (bool) {
        return completed[keccak256(abi.encodePacked(_orderId, _chainIdFrom, _timestampFrom))];
    }

    function getOrder(uint256 _orderId) public view returns (Order memory) {
        return orders[_orderId];
    }

    function calculateFee(
        uint256 _tokenId,
        uint256 _chainId,
        uint256 _amount
    ) public view returns (uint256 feeAmount) {
        Token memory tok = tokens[_tokenId];
        Config memory config = bridgeTokenToChainConfig[_tokenId][_chainId];

        uint256 fee = uint256(tok.defaultFee);
        uint256 feeBase = tok.defaultFeeBase;

        if (config.fee > 0) {
            fee = uint256(config.fee);
        }
        if (config.feeBase > 0) {
            feeBase = config.feeBase;
        }

        feeAmount = feeBase + (_amount * fee) / DIVIDER;
    }

    function checkFee(
        uint256 _tokenId,
        uint256 _chainId,
        uint256 _amount
    ) public view returns (bool) {
        return _amount > calculateFee(_tokenId, _chainId, _amount);
    }

    function tokensMintBurnLogicListContains(address _token) public view returns (bool) {
        return _tokensMintBurnLogicList.contains(_token);
    }

    function _transferFee(
        uint256 _tokenId,
        uint256 _chainId,
        uint256 _amount
    ) private returns (uint256 feeAmount) {
        Token memory tok = tokens[_tokenId];

        feeAmount = calculateFee(_tokenId, _chainId, _amount);
        if (feeAmount > _amount) feeAmount = _amount;
        if (feeAmount > 0 && tok.feeTarget != address(this)) {
            tok.token.safeTransfer(tok.feeTarget, feeAmount);
        }
    }

    function _checkAmount(
        uint256 _tokenId,
        uint256 _chainId,
        uint256 _amount
    ) private view returns (bool) {
        Token memory tok = tokens[_tokenId];
        Config memory config = bridgeTokenToChainConfig[_tokenId][_chainId];

        uint256 min = tok.defaultMinAmount;
        uint256 max = tok.defaultMaxAmount;

        if (config.minAmount > 0) {
            min = config.minAmount;
        }
        if (config.maxAmount > 0) {
            max = config.maxAmount;
        }

        return _amount >= min && _amount <= max;
    }

    function _tokenDecimals(IERC20Metadata _token) private view returns (uint256) {
        return _token.decimals();
    }

    function _convertAmount(
        IERC20Metadata _token,
        uint256 _amount,
        uint256 _fromDecimals
    ) private view returns (uint256) {
        return (_amount * (10 ** _tokenDecimals(_token))) / (10 ** _fromDecimals);
    }
}

