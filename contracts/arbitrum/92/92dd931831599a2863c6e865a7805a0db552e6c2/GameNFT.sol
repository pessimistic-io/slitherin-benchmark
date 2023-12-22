// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

error NotAdmin(address msgSender);
error NotClient(address msgSender);
error NoActivityYet(uint256 term);
error NotAddEvent(uint256 term);
error NotEditEvent(uint256 term);
error TokenLimitReached(uint256 startTokenId, uint256 bought, uint256 endTokenId);
error PurchaseOverLimit(uint256 buyLimits, uint256 buyLimit);
error ValueError(uint256 value, uint256 price);
error NotEventStart(uint256 nowTime, uint256 startTime);
error EventEnd(uint256 nowTime, uint256 endTime);

// NFT
contract NFT is ERC721EnumerableUpgradeable, OwnableUpgradeable, IERC721ReceiverUpgradeable {

    mapping(address => bool) public admin;
    string public baseURI;

     //// Events
    struct EventInfo {
        uint256 term; //
        uint256 startTime; //
        uint256 endTime; //
        uint256 startTokenId; //
        uint256 endTokenId; //
        uint256 price; //
        uint256 buyLimit; //
    }

    uint256 public nowTerm; //（）
    mapping(uint256 => EventInfo) public eventInfos; //
    mapping(uint256 => bool) public eventMap;
    mapping(uint256 => uint256) public indices; //tokenId 
    mapping(uint256 => uint256) public bought; //
    mapping(address => mapping(uint256 => uint256)) public buyLimits;
    

    //  token , 
    mapping(uint256 => uint256) public tokenTerm; // key=tokenId, value=

    event eventMultiNftDeposit(address indexed from_addr, address indexed to, uint256[] tokenIds);
    event eventMultiWithdraw(address indexed from_addr, address indexed to, uint256[] tokenIds);
    event eventWithdraw(address indexed from, address indexed to, uint256 indexed tokenId);

    modifier checkAdmin()
    {   
        if(!admin[_msgSender()])
        {
            revert NotAdmin(_msgSender());
        }
        _;
    }

    modifier checkEventsStatus()
    {   
        // 
        if(!eventMap[nowTerm])
        {
            revert NoActivityYet(nowTerm);
        }
        
        // 
        if(eventInfos[nowTerm].startTokenId + bought[nowTerm] - 1 >= eventInfos[nowTerm].endTokenId)
        {
            revert TokenLimitReached(eventInfos[nowTerm].startTokenId, bought[nowTerm], eventInfos[nowTerm].endTokenId);
        }

        // 
        if(buyLimits[_msgSender()][nowTerm] >= eventInfos[nowTerm].buyLimit)
        {
            revert PurchaseOverLimit(buyLimits[_msgSender()][nowTerm], eventInfos[nowTerm].buyLimit);
        }

        // 
        if(msg.value < eventInfos[nowTerm].price)
        {
            revert ValueError(msg.value, eventInfos[nowTerm].price);
        }

        // 
        if(block.timestamp < eventInfos[nowTerm].startTime)
        {
            revert NotEventStart(block.timestamp, eventInfos[nowTerm].startTime);
        }

        // 
        if(block.timestamp >= eventInfos[nowTerm].endTime)
        {
            revert EventEnd(block.timestamp, eventInfos[nowTerm].endTime);
        }
        _;
    }

    struct OwnerInfo
    {
        uint256 _tokenId;
        address _addr;
    }

    function initialize() public initializer
    {
        __ERC721_init("NFT", "NFT");
        __Ownable_init();
    }

    function setAdmin(address _sender, bool _flag) public onlyOwner
    {
        admin[_sender] = _flag;
    }

    function approveForContract(address operator, bool _flag) public onlyOwner
    {
        _setApprovalForAll(address(this), operator, _flag);
    }

    function _baseURI() internal override view virtual returns (string memory)
    {
        return baseURI;
    }

    function setBaseURI(string calldata base_uri) public checkAdmin
    {
        baseURI = base_uri;
    }

    function getAllTokensByOwner(address _account) external view returns (uint256[] memory)
    {
        uint256 length = balanceOf(_account);
        uint256[] memory result = new uint256[](length);

        for (uint i = 0; i < length; i++)
            result[i] = tokenOfOwnerByIndex(_account, i);

        return result;
    }

    function multiWithdraw(address from, address to, uint256[] memory tokenIds) external checkAdmin
    {
        for (uint256 i = 0; i < tokenIds.length; i++)
        {
            if (!_exists(tokenIds[i]))
            {
                _safeMint(to, tokenIds[i]);
            }
            else
            {
                safeTransferFrom(from, to, tokenIds[i]);
            }
        }

        emit eventMultiWithdraw(from, to, tokenIds);
    }

    function multiNftDeposit(address from, address to, uint256[] memory tokenIds) external
    {
        for (uint256 i = 0; i < tokenIds.length; i++)
        {
            safeTransferFrom(from, to, tokenIds[i]);
        }

        emit eventMultiNftDeposit(from, to, tokenIds);
    }

    function multiNftDepositTransfer(address to, uint256[] memory tokenIds) external
    {
        for (uint256 i = 0; i < tokenIds.length; i++)
        {
            _safeTransfer(_msgSender(), to, tokenIds[i], "");
        }

        emit eventMultiNftDeposit(_msgSender(), to, tokenIds);
    }

    function mintFromMapping(OwnerInfo[] memory _ownerInfo) external checkAdmin
    {
        for (uint256 i = 0; i < _ownerInfo.length; i++)
        {
            _safeMint(_ownerInfo[i]._addr, _ownerInfo[i]._tokenId);
        }
    }

    // 
    function setEventInfo(
        uint256 _term,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _startTokenId,
        uint256 _endTokenId,
        uint256 _price,
        uint256 _buyLimit
    ) public checkAdmin
    {   
        if(eventMap[_term])
        {
            revert NotAddEvent(_term);
        }

        EventInfo memory o = EventInfo({
            term : _term,
            startTime : _startTime,
            endTime : _endTime,
            startTokenId : _startTokenId,
            endTokenId : _endTokenId,
            price : _price ,
            buyLimit : _buyLimit
        });
        eventInfos[_term] = o;
        eventMap[_term] = true;
        indices[_term] = _startTokenId;
    }

    // 
    function editEvents(
        uint256 _term,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _buyLimit
    ) public checkAdmin
    {
        if(!eventMap[_term])
        {
            revert NotEditEvent(_term);
        }

        eventInfos[_term].startTime = _startTime;
        eventInfos[_term].endTime = _endTime;
        eventInfos[_term].buyLimit = _buyLimit;
    }

    // 
    function setNowTerm(uint256 _term) public checkAdmin
    {
        nowTerm = _term;
    }

    function mint() external payable checkEventsStatus
    {   
        
        uint256 id = indices[nowTerm];
        indices[nowTerm] ++;
        bought[nowTerm] ++;
        buyLimits[_msgSender()][nowTerm] ++;

        _safeMint(_msgSender(), id);

        tokenTerm[id] = nowTerm;
    }

    // 
    function extract(address payable _address) public checkAdmin
    {
        _address.transfer(address(this).balance);
    }

    // , 
    function withdraw(address _from, address _to, uint256 _tokenId) external checkAdmin
    {
        if (!_exists(_tokenId))
        {
            _safeMint(_to, _tokenId);
        }
        else
        {
            safeTransferFrom(_from, _to, _tokenId);
        }

        emit eventWithdraw(_from, _to, _tokenId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override pure returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}
