// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC721Holder.sol";
import "./IERC721.sol";
import "./Pausable.sol";
import "./IERC721Enumerable.sol";
import "./ReentrancyGuard.sol";

contract multiSign is Pausable, ERC721Holder, Ownable, ReentrancyGuard
{
    event Deposit(address indexed sender, uint amount, uint balance);
    event SubmitTransaction(address indexed owner, uint indexed txIndex, address[] indexed to, uint256[] value);
    event ConfirmTransaction(address indexed owner, uint indexed txIndex);
    event ExecuteTransactionNativeToken(address indexed owner, uint indexed txIndex);
    event ExecuteTransactionToken(address indexed owner, uint indexed txIndex);
    event ExecuteTransactionNFT(address indexed owner, uint indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint indexed txIndex);

    mapping(address => bool) public signerList;
    address public transOperator = 0xf06A38607d8C5aF33d4290e5D4a6a22Dd59ff440;
    uint256 public numConfirmationsRequired;

    mapping(address => bool) public addressList;

    address[] public signersArray;

    struct Transaction{
        address contractAddress;
        address[] to;
        uint256[] value;
        bool initTrans;
        bool executed;
        uint numConfirmations;
        mapping(address => bool) isComfirmed;
        address[] signers;
    }

    mapping(uint256 => Transaction) public transactions;
    constructor()
    {
    }

    modifier isSigner()
    {
        require(signerList[msg.sender], "You are not an operator");
        _;
    }

    modifier isTransOperator()
    {
        require(transOperator == msg.sender, "You are not transOperator");
        _;
    }

    modifier notExecuted(uint _txIndex)
    {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }

    modifier notConfirmed(uint _txIndex)
    {
        require(!transactions[_txIndex].isComfirmed[msg.sender], "tx already confirmed");
        _;
    }

    modifier isInitTrans(uint _txIndex)
    {
        require(transactions[_txIndex].initTrans, "tx did not create");
        _;
    }

    function editNumConfirmationsRequired(uint256 _numConfirmationsRequired) external onlyOwner
    {
        numConfirmationsRequired = _numConfirmationsRequired;
    }

    function addSignerList(address[] memory _singers,bool state ,uint _numConfirmationsRequired) external onlyOwner
    {
        require(_singers.length > 0, "Operators required");
        require(_numConfirmationsRequired > 0 && _numConfirmationsRequired <= _singers.length, "Error");
        for(uint i = 0; i < _singers.length; i++)
        {
            require(_singers[i] != address(0), "Invalid owner");
            require(!signerList[_singers[i]], "Owner not unique");
            signerList[_singers[i]] = state;
            signersArray.push(_singers[i]);
        }
        numConfirmationsRequired = _numConfirmationsRequired;
    }

    function editWhitelistAddress(address _addr, bool state) external onlyOwner
    {
        addressList[_addr] = state;
    }

    function editSigner(address _addr, bool state) external onlyOwner
    {
        signerList[_addr] = state;
    }

    function editTransOperator(address _transOperator) external onlyOwner
    {
        transOperator = _transOperator;
    }



    function submitTransaction(uint _txIndex, address[] memory _to, uint256[] memory _value, address _addr)
    external
    nonReentrant
    isTransOperator()
    notExecuted(_txIndex)
    {
        require(addressList[_addr], "Address is not available");
        require(_to.length == _value.length, "Error same length");
        Transaction storage info = transactions[_txIndex];
        for(uint i = 0; i < _to.length; i++)
        {
            info.to.push(_to[i]);
            info.value.push(_value[i]);
        }
        info.contractAddress = _addr;
        info.initTrans = true;
        info.executed = false;
        info.numConfirmations = 0;
        info.isComfirmed[msg.sender]=false;
        emit SubmitTransaction(msg.sender, _txIndex, _to, _value);
    }

    function confirmTransaction(uint _txIndex)
    external
    nonReentrant
    notConfirmed(_txIndex)
    notExecuted(_txIndex)
    isSigner()
    isInitTrans(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.isComfirmed[msg.sender] = true;
        transaction.signers.push(msg.sender);
        transaction.numConfirmations +=1;

        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeTransactionNativeToken(uint _txIndex, address _addr)
    external
    nonReentrant
    isTransOperator()
    notExecuted(_txIndex)
    {
        require(addressList[_addr], "Address is not available");
        Transaction storage transaction = transactions[_txIndex];
        require(transaction.contractAddress == _addr, "Addresses does not match");
        require(transaction.numConfirmations >= numConfirmationsRequired, "Can not execute tx");
        transaction.executed = true;
        address[] memory _to = transaction.to;
        uint256[] memory _value = transaction.value;
        for(uint i = 0; i < _to.length; i++)
        {
            payable(_to[i]).transfer(_value[i]);
        }
        emit ExecuteTransactionNativeToken(msg.sender, _txIndex);
    }

    function executeTransactionToken(uint _txIndex, address _addr)
    external
    nonReentrant
    isTransOperator()
    notExecuted(_txIndex)
    {
        require(addressList[_addr], "Address is not available");
        Transaction storage transaction = transactions[_txIndex];
        require(transaction.contractAddress == _addr, "Addresses does not match");
        require(transaction.numConfirmations >= numConfirmationsRequired, "Can not execute tx");
        transaction.executed = true;
        address[] memory _to = transaction.to;
        uint256[] memory _value = transaction.value;
        for(uint i = 0; i < _to.length; i++)
        {
            ERC20(transaction.contractAddress).transfer(_to[i],_value[i]);
        }
        emit ExecuteTransactionToken(msg.sender, _txIndex);
    }

    function executeTransactionNFT(uint _txIndex, address _addr)
    external
    nonReentrant
    isTransOperator()
    notExecuted(_txIndex)
    {
        require(addressList[_addr], "Address is not available");
        Transaction storage transaction = transactions[_txIndex];
        require(transaction.contractAddress == _addr, "Addresses does not match");
        require(transaction.numConfirmations >= numConfirmationsRequired, "Can not execute tx");
        transaction.executed = true;
        address[] memory _to = transaction.to;
        uint256[] memory _value = transaction.value;
        for(uint i = 0; i < _to.length; i++)
        {
            IERC721(transaction.contractAddress).safeTransferFrom(address(this), _to[i],_value[i]);
        }
        emit ExecuteTransactionNFT(msg.sender, _txIndex);
    }

    function readSignersOnTransaction(uint _txIndex) external view returns(address[] memory)
    {
        address[] memory _signersList = transactions[_txIndex].signers;
        address[] memory path;
        path  = new address[](_signersList.length);
        for(uint i =0; i < _signersList.length; i++)
        {
            path[i]=_signersList[i];
        }
        return path;
    }

    function viewSignerList() external view returns(address[] memory)
    {
        return signersArray;
    }



    function revokeConfirmation(uint _txIndex)
    external
    onlyOwner
    nonReentrant
    {
        delete transactions[_txIndex];
        emit RevokeConfirmation(msg.sender, _txIndex);
    }


    // amount BNB
    function withdrawNative(uint256 _amount, address _beneficiary) public onlyOwner {
        require(_amount > 0 , "_amount must be greater than 0");
        require( address(this).balance >= _amount ,"balanceOfNative:  is not enough");
        payable(_beneficiary).transfer(_amount);
    }

    function withdrawToken(IERC20 _token, uint256 _amount, address _beneficiary) public onlyOwner {
        require(_amount > 0 , "_amount must be greater than 0");
        require(_token.balanceOf(address(this)) >= _amount , "balanceOfToken:  is not enough");
        _token.transfer(_beneficiary, _amount);
    }

    // all BNB
    function withdrawNativeAll() external onlyOwner {
        require(address(this).balance > 0 ,"balanceOfNative:  is equal 0");
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawTokenAll(IERC20 _token) public onlyOwner {
        require(_token.balanceOf(address(this)) > 0 , "balanceOfToken:  is equal 0");
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

    function withdrawNFT(uint256 _tokenId, address _beneficiary, address erc721) public onlyOwner{
        IERC721(erc721).safeTransferFrom(address(this), _beneficiary, _tokenId);
    }

    function withdrawAllNFT(address _beneficiary, address erc721) external onlyOwner{
        uint256 _amountBox = IERC721Enumerable(erc721).balanceOf(address(this));
        for (uint256 i = 0; i < _amountBox; i++) {
            uint256 _tokenId = IERC721Enumerable(erc721).tokenOfOwnerByIndex(address(this), 0);
            IERC721(erc721).safeTransferFrom(address(this), _beneficiary, _tokenId);
        }
    }

    event Received(address, uint);
    receive () external payable {
        emit Received(msg.sender, msg.value);
    }
}
