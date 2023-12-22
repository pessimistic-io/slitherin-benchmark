// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./console.sol";

contract YcLPer {
  /**
   * @notice The address of the YC contract
   */

  address public owner;

  constructor() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, 'Only owner can call this function');
    _;
  }

  /**
   * @notice A mapping of strings => Client structs.
   * Only accessible to owner
   */

  mapping(string => Client) internal clients;

  /**
   * @notice Manipulation of the clients mapping
   */

  function addClient(
    string memory clientName,
    string memory erc20FunctionSig,
    string memory ethFunctionSig,
    string memory erc20RemoveFunctionSig,
    string memory ethRemoveFunctionSig,
    string memory balanceOfSig,
    string memory getAmountsOutSig,
    string memory getAmountsInSig,
    string memory factoryFunctionSig,
    string memory getReservesSig,
    string memory getPairSig,
    bool isSingleFunction,
    bool isStandard,
    address clientAddress
  ) public onlyOwner {
    clients[clientName] = Client(
      erc20FunctionSig,
      ethFunctionSig,
      erc20RemoveFunctionSig,
      ethRemoveFunctionSig,
      balanceOfSig,
      getAmountsOutSig,
      getAmountsInSig,
      factoryFunctionSig,
      getReservesSig,
      getPairSig,
      isSingleFunction,
      isStandard,
      clientAddress
    );
  }

  function getClient(string memory clientName)
    public
    view
    returns (Client memory)
  {
    return clients[clientName];
  }

  /**
   * @notice Struct containing the function signatures of clients
   * @param erc20FunctionSig String containing the function signature of the ERC20 addLiquidity function
   * @param wethFunctionSig String containing the function signature of the WETH addLiquidity function
   * @param getAmountsOutSig String containing the function signature of the getAmountsOut function
   * @param isSingleFunction Boolean indicating whether the client has a single function or two functions
   * @param isStandard Boolean indicating whether the client is a standard LP or a custom implementation contract
   * @dev If the client is a non-standard LP, then the call with the exact inputted full parameters will be
   * delegated onto the ERC20
   * function sigs, and the logic will be handled by a custom logic contract. If it is standard,
   * then the logic will be handled
   * by the contract itself - It can either be called with the ycSingleFunction
   * (i.e if one function handles addLiquidity), or with
   * the ycTwoFunctions (i.e if two functions handle addLiquidity with a case for ERC20s and ETH).
   */
  struct Client {
    string erc20FunctionSig; // Sig being signed when calling AddLiquidity on an ERC20 / Orchestrator function
    string ethFunctionSig; // Sig being signed when calling AddLiquidity on WETH
    string erc20RemoveFunctionSig; // Sig being signed when calling RemoveLiquidity on an ERC20 / Orchestrator function
    string ethRemoveFunctionSig; // Sig being signed when calling RemoveLiquidity on WETH
    string balanceOfSig; // Sig being called when getting the balance of an LP token pair
    string getAmountsOutSig; // Sig being called when getting the amounts out of a swap
    string getAmountsInSig; // Sig being called when getting the amounts in of a swap
    string factoryFunctionSig; // Sig being called when getting the factory address of a client
    string getReservesSig; // Sig being called when getting the reserves of a pair
    string getPairSig; // Sig being called when getting the pair address of a client (on it's factory address)
    bool isSingleFunction; // Boolean, whether the client has one function or two functions (ERC20 & WETH / single one)
    bool isStandard; // Indicating whether the client is a standard UNI-V2 LP or a custom implementation contract.
    address clientAddress; // Address of the client
  }

  /**
   *  -------------------------------------------------------------
   * @notice Gets a token balance for a token address and user address
   *  -------------------------------------------------------------
   */
  function getTokenOrEthBalance(address tokenAddress, address userAddress)
    public
    view
    returns (uint256)
  {
    bool success;
    bytes memory result;

    // Return native currency balance in the case of the 0 address being provided
    if (tokenAddress == address(0)) {
      return userAddress.balance;
    }

    // Call the ERC20 balanceOf function, return that
    (success, result) = tokenAddress.staticcall(
      abi.encodeWithSignature('balanceOf(address)', userAddress)
    );

    require(success, 'Failed to get token balance');

    return abi.decode(result, (uint256));
  }

  /**
   *  -------------------------------------------------------------
   * @notice gets the address of a pair from the inputted token addresses, and the client's name
   * -------------------------------------------------------------
   */
  function getPairByClient(
    Client memory client,
    address tokenAAddress,
    address tokenBAddress
  ) internal view returns (address) {
    bool success;
    bytes memory result;
    (success, result) = client.clientAddress.staticcall(
      abi.encodeWithSignature(client.factoryFunctionSig)
    );

    require(success, 'Failed To Get Factory Address For Client');

    address factoryAddress = abi.decode(result, (address));

    (success, result) = factoryAddress.staticcall(
      abi.encodeWithSignature(client.getPairSig, tokenAAddress, tokenBAddress)
    );

    require(success, 'Failed To Get Pair Address For Client');

    return abi.decode(result, (address));
  }

  /**
   * -------------------------------------------------------------
   * @notice Takes in an amount, token A & B addresses - returns the amount needed for
   * token B when adding liquidity with the token A amount, on any supported client
   * -------------------------------------------------------------
   */
  function getAmountOutByClient(
    Client memory client,
    uint256 amountIn,
    address tokenInAddress,
    address tokenOutAddress
  ) internal returns (uint256) {
    // Get amount out from the client
    address[] memory path = new address[](2);

    path[0] = tokenInAddress;
    path[1] = tokenOutAddress;
    (bool success, bytes memory result) = client.clientAddress.call(
      abi.encodeWithSignature(client.getAmountsOutSig, amountIn, path)
    );

    console.log('Amount In', amountIn);
    console.log('Token In Address', tokenInAddress);
    console.log('Token Out Address', tokenOutAddress);

    require(success, 'Failed To Get Amount Out For Client');

    // Return the amount out (we get an array where the first element is the amount
    // we entered and the second one is what we're looking for)
    return abi.decode(result, (uint256[]))[1];
  }

  /**
   * @notice Gets the reserves of a pair on a client
   */
  function getReservesByClient(address pair, Client memory client)
    internal
    view
    returns (uint256, uint256)
  {
    (bool success, bytes memory result) = pair.staticcall(
      abi.encodeWithSignature(client.getReservesSig)
    );

    require(success, 'Failed To Get Reserves For Client');

    return abi.decode(result, (uint256, uint256));
  }
}

