pragma solidity ^0.5.0;

/**
  * @title DSMath
  * @author ERC20 Authors? Vitalik B. Fabian V.
  * @notice ERC20Interface
  */
contract ERC20 {
    function transferFrom(address from, address to, uint256 tokens) public returns (bool success);
    function transfer(address to, uint256 tokens) public returns (bool success);
}

/**
  * @title DSMath
  * @author MakerDAO
  * @notice Safe math contracts from Maker.
  */
contract DSMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }
    function max(uint x, uint y) internal pure returns (uint z) {
        return x >= y ? x : y;
    }
    function imin(int x, int y) internal pure returns (int z) {
        return x <= y ? x : y;
    }
    function imax(int x, int y) internal pure returns (int z) {
        return x >= y ? x : y;
    }

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), RAY / 2) / RAY;
    }
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, RAY), y / 2) / y;
    }

    // This famous algorithm is called "exponentiation by squaring"
    // and calculates x^n with x as fixed-point and n as regular unsigned.
    //
    // It's O(log n), instead of O(n) for naive repeated multiplication.
    //
    // These facts are why it works:
    //
    //  If n is even, then x^n = (x^2)^(n/2).
    //  If n is odd,  then x^n = x * x^(n-1),
    //   and applying the equation for even x gives
    //    x^n = x * (x^2)^((n-1) / 2).
    //
    //  Also, EVM division is flooring and
    //    floor[(n-1) / 2] = floor[n / 2].
    //
    function rpow(uint x, uint n) internal pure returns (uint z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }
}

/**
  * @title MetaTransactionPool
  * @author Nick Dodson <thenickdodson@gmail.com>
  * @notice A meta-transaction relay pool for ERC20's / Ether
  */
contract MetaTransactionPool is DSMath {
  bytes32 constant public SIGNEDTRANSFER_TYPEHASH = keccak256("Transfer(address recipient,bytes11 nonce,bool useSignature,bool useApproved,address token,uint256 amount,address feeRecipient,uint256 fee,uint256 expiry)");
  bytes32 public DOMAIN_SEPARATOR = keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"), // EIP712
    keccak256("MetaTransactionPool"), // app name
    keccak256("1"), // app version
    uint256(1), // chain id
    address(this), // verifying contract
    keccak256("take-a-dip-in-the-pool") // salt
  ));

  enum DestinationKinds { Claim, ClaimAndMove, Move, Shift }

  mapping(address => mapping(bytes32 => bool)) public invalidatedHashes; // all used or invalided hashes
  mapping(address => mapping(address => uint256)) public tokenBalances;

  event Deposit(address sender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint tokens, bytes32 releaseHash);

  // payable for eth payments..
  function deposit() payable external {
    tokenBalances[msg.sender][address(0)] = add(tokenBalances[msg.sender][address(0)], msg.value);

    emit Deposit(msg.sender, msg.value);
  }

  // invalidate release hashes
  function invalidateHash(bytes32 releaseHash) external {
    invalidatedHashes[msg.sender][releaseHash] = true;
  }

  // destination := bytes1(type)bytes11(nonce)bytes20(address)
  // transfer eth / erc20 into / out of / around MetaTxPool
  function transfer(
    bytes32 destination, // 0x00 or 01 or 02 ... 0000 ... address
    address token,
    uint256 amount,
    address payable feeRecipient,
    uint256 fee,
    uint256 expiry,
    bytes32[] calldata signatures) external {
    // Recipient Address
    address payable recipient = address(uint160(uint256(destination)));

    // Is the final destinaiton the Pool or Their Account
    DestinationKinds kind = DestinationKinds(uint8(destination[0]));

    // sender created release hash EIP712 compliant
    bytes32 releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      DOMAIN_SEPARATOR,
      keccak256(abi.encode(
        SIGNEDTRANSFER_TYPEHASH,
        (signatures.length == 6)
          ? ecrecover(destination, uint8(signatures[3][31]), signatures[4], signatures[5])
          : recipient,
        bytes11(destination << 8),
        signatures.length == 6 ? true : false,
        uint8(kind) <= 1 ? true : false, // allow the use of Approved funds or false for only internal
        token, amount, feeRecipient, fee, expiry))
      ));
    address from = ecrecover(releaseHash, uint8(signatures[0][31]), signatures[1], signatures[2]); // recover creator signature

    // Check release hash and specified expiry
    assert(invalidatedHashes[from][releaseHash] == false
        && block.timestamp < expiry);

    invalidatedHashes[from][releaseHash] = true; // nullify release hash

    emit Transfer(from, recipient, amount, releaseHash); // transfer event

    // claim, but leave in MetaTxPool contract
    if (kind == DestinationKinds.Claim) {
      if (token != address(0))
        ERC20(token).transferFrom(from, address(this), add(amount, fee)); // transfer tokens to destination
      else
        tokenBalances[from][token] = sub(tokenBalances[from][token], add(amount, fee));

      tokenBalances[recipient][token] = add(tokenBalances[recipient][token], amount);
      tokenBalances[(feeRecipient == address(0) ? msg.sender : feeRecipient)][token] = add(tokenBalances[(feeRecipient == address(0) ? msg.sender : feeRecipient)][token], fee);

      return;
    }

    // Claim and Move crypto to Recipient Address
    if (kind == DestinationKinds.ClaimAndMove) {
      if (token != address(0)) {
        ERC20(token).transferFrom(from, recipient, amount); // transfer tokens to destination
        ERC20(token).transferFrom(from, (feeRecipient == address(0) ? msg.sender : feeRecipient), fee); // transfer tokens to destination
      } else {
        tokenBalances[from][token] = sub(tokenBalances[from][token], add(amount, fee));

        recipient.transfer(amount);
        (feeRecipient == address(0) ? msg.sender : feeRecipient).transfer(fee);
      }

      return;
    }

    // Move funds out of MetaTxPool
    if (kind == DestinationKinds.Move) {
      tokenBalances[from][token] = sub(tokenBalances[from][token], add(amount, fee));

      if (token != address(0)) {
        ERC20(token).transfer(recipient, amount); // transfer tokens to destination
        ERC20(token).transfer((feeRecipient == address(0) ? msg.sender : feeRecipient), fee); // transfer tokens to destinatio
      } else {
        recipient.transfer(amount);
        (feeRecipient == address(0) ? msg.sender : feeRecipient).transfer(fee);
      }

      return;
    }

    // Transfer within MetaTxPool from one account to another
    if (kind == DestinationKinds.Shift) {
      tokenBalances[from][token] = sub(tokenBalances[from][token], add(amount, fee));
      tokenBalances[recipient][token] = add(tokenBalances[recipient][token], amount);
      tokenBalances[(feeRecipient == address(0) ? msg.sender : feeRecipient)][token] = add(tokenBalances[(feeRecipient == address(0) ? msg.sender : feeRecipient)][token], fee);

      return;
    }
  }
}

/// @title MultiCallNoThrow - Allows to batch multiple transactions into one. But this one doesn't throw if tx !success
/// @author Nick Dodson - <nick.dodson@consensys.net>
/// @author Gonçalo Sá - <goncalo.sa@consensys.net>
/// @author Stefan George - <stefan@gnosis.pm>
contract MultiCallNoThrow {
    /// @dev Sends multiple transactions and does not revert if tx fails.
    /// @param data Encoded transactions. Each transaction is encoded as a
    ///                     tuple(address,uint256,bytes), where operation
    ///                     can be 0 for a call or 1 for a delegatecall. The bytes
    ///                     of all encoded transactions are concatenated to form the input.
    function multiSend(uint256 gass, address to, uint256 value, uint256 dataLength, uint256 count, bytes memory data) public {
       // solium-disable-next-line security/no-inline-assembly
        assembly {
            let i := 0x20
            let length := add(0x20, mul(dataLength, count))
            for { } lt(i, length) { } {
                pop(call(gass, to, value, add(data, i), dataLength, 0, 0))
                i := add(i, dataLength)
            }
        }
    }
}
