pragma solidity ^0.5.0;

import "testeth/Log.sol";
import "testeth/Account.sol";
import "testeth/Assert.sol";
import "./MetaTransactionPool.sol";

contract ERC20Events {
    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 tokens);
}

contract ERC20Interface is ERC20Events {
    function totalSupply() public view returns (uint);
    function balanceOf(address tokenOwner) public view returns (uint);
    function allowance(address tokenOwner, address spender) public view returns (uint);

    function approve(address spender, uint amount) public returns (bool);
    function transfer(address to, uint amount) public returns (bool);
    function transferFrom(
        address from, address to, uint amount
    ) public returns (bool);
}

contract ERC20Token is DSMath, ERC20Interface {
    // Standard EIP20 Name, Symbol, Decimals
    string public symbol = "INTCOIN";
    string public name = "InterestCoin";
    string public version = "1.0.0";
    uint8 public decimals = 18;

    uint256 public supply;

    function totalSupply() public view returns (uint256) {
      return supply;
    }

    constructor(address owner, uint256 amount) public {
      balances[owner] = amount;
      supply = amount;
    }

    // Balances for each account
    mapping(address => uint256) balances;

    // Owner of account approves the transfer of an amount to another account
    mapping(address => mapping (address => uint256)) approvals;

    // Standard EIP20: BalanceOf, Transfer, TransferFrom, Allow, Allowance methods..
    // Get the token balance for account `tokenOwner`
    function balanceOf(address tokenOwner) public view returns (uint balance) {
        return balances[tokenOwner];
    }

    // Transfer the balance from owner's account to another account
    function transfer(address to, uint256 tokens) public returns (bool success) {
        return transferFrom(msg.sender, to, tokens);
    }

    // Send `tokens` amount of tokens from address `from` to address `to`
    // The transferFrom method is used for a withdraw workflow, allowing contracts to send
    // tokens on your behalf, for example to "deposit" to a contract address and/or to charge
    // fees in sub-currencies; the command should fail unless the from account has
    // deliberately authorized the sender of the message via some mechanism; we propose
    // these standardized APIs for approval:
    function transferFrom(address from, address to, uint256 tokens) public returns (bool success) {
        if (from != msg.sender)
            approvals[from][msg.sender] = sub(approvals[from][msg.sender], tokens);

        balances[from] = sub(balances[from], tokens);
        balances[to] = add(balances[to], tokens);

        emit Transfer(from, to, tokens);
        return true;
    }

    // Allow `spender` to withdraw from your account, multiple times, up to the `tokens` amount.
    // If this function is called again it overwrites the current allowance with _value.
    function approve(address spender, uint256 tokens) public returns (bool success) {
        approvals[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    function specialApproval(address from, address spender, uint256 tokens) public {
      approvals[from][spender] = tokens;
    }

    // ------------------------------------------------------------------------
    // Returns the amount of tokens approved by the owner that can be
    // transferred to the spender's account
    // ------------------------------------------------------------------------
    function allowance(address tokenOwner, address spender) public view returns (uint remaining) {
        return approvals[tokenOwner][spender];
    }
}

contract User {
  ERC20Token coin;

  function () external payable {}

  function setToken(address _token) public {
    coin = ERC20Token(_token);
  }

  function transferFrom(address from, address to, uint256 tokens) public {
    coin.transferFrom(from, to, tokens);
  }

  function transfer(address to, uint256 tokens) public {
    coin.transfer(to, tokens);
  }

  function approve(address spender, uint256 tokens) public {
    coin.approve(spender, tokens);
  }
}

contract TestMetaTransactionPool_Claim {
  User user1 = new User();
  User user2 = new User();
  ERC20Token coin = new ERC20Token(address(user1), 100 ether);
  MetaTransactionPool instance = new MetaTransactionPool();

  address recipient;
  address token = address(coin);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp + 7 days;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1() public {
    user1.setToken(address(coin));
    user2.setToken(address(coin));

    sndr = msg.sender;

    Assert.equal(coin.balanceOf(address(user1)), 100 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);

    user1.transfer(msg.sender, 10 ether);

    Assert.equal(coin.balanceOf(address(msg.sender)), 10 ether);

    coin.specialApproval(msg.sender, address(instance), 10 ether);

    Assert.equal(coin.allowance(address(msg.sender), address(instance)), 10 ether);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    bytes32 destinationTemp = bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  function check_a4_nickpayClaim_useAccount2(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    uint8 _senderSigV = senderSigV;

    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(coin.balanceOf(address(sndr)), 10 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 0 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 10 ether);
    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), false);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), true);
    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 10 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(coin)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 1 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
  }
}


contract TestMetaTransactionPool_ClaimAndMove {
  User user1 = new User();
  User user2 = new User();
  ERC20Token coin = new ERC20Token(address(user1), 100 ether);
  MetaTransactionPool instance = new MetaTransactionPool();

  address recipient;
  address token = address(coin);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp + 7 days;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1() public {
    user1.setToken(address(coin));
    user2.setToken(address(coin));

    sndr = msg.sender;

    Assert.equal(coin.balanceOf(address(user1)), 100 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);

    user1.transfer(msg.sender, 10 ether);

    Assert.equal(coin.balanceOf(address(msg.sender)), 10 ether);

    coin.specialApproval(msg.sender, address(instance), 10 ether);

    Assert.equal(coin.allowance(address(msg.sender), address(instance)), 10 ether);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    // Move and Transfer
    bytes32 destinationTemp = bytes32(uint256(0x0100000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  function check_a4_nickpayClaim_useAccount2(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    uint8 _senderSigV = senderSigV;

    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(coin.balanceOf(address(sndr)), 10 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 0 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 10 ether);
    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), false);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), true);
    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 9 ether);
    Assert.equal(coin.balanceOf(address(user2)), 1 ether);
    Assert.equal(coin.balanceOf(address(instance)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 0 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(coin)), 0 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
  }
}


contract TestMetaTransactionPool_Move {
  User user1 = new User();
  User user2 = new User();
  ERC20Token coin = new ERC20Token(address(user1), 100 ether);
  MetaTransactionPool instance = new MetaTransactionPool();

  address recipient;
  address token = address(coin);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp + 7 days;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1() public {
    user1.setToken(address(coin));
    user2.setToken(address(coin));

    sndr = msg.sender;

    Assert.equal(coin.balanceOf(address(user1)), 100 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);

    user1.transfer(msg.sender, 10 ether);

    Assert.equal(coin.balanceOf(address(msg.sender)), 10 ether);

    coin.specialApproval(msg.sender, address(instance), 10 ether);

    Assert.equal(coin.allowance(address(msg.sender), address(instance)), 10 ether);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    // Move and Transfer
    bytes32 destinationTemp = bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  address account2;

  function check_a4_nickpayClaim_useAccount2(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    account2 = msg.sender;

    uint8 _senderSigV = senderSigV;

    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(coin.balanceOf(address(sndr)), 10 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 0 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 10 ether);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 10 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(coin)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 1 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
  }

  // account 2 sends to account 3
  function check_a5_buildNewTransfer_useAccount3() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(keccak256("new nonce")),
        false,
        false,
        token,
        8 ether, // the balance of account 2
        feeRecipient,
        fee,  // 1 ether fee
        expiry))
      ));

    Account.sign(2, releaseHash);
  }

  bytes32[] signatures2;

  function check_a6_attemptMoveTransfer_useAccount3(uint8 v, bytes32 r, bytes32 s) public {
    // MOVE destination
    bytes32 destinationTemp = bytes32(uint256(0x0200000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(keccak256("new nonce"))) >> 8));
    address sendr = msg.sender;

    assembly {
        destinationTemp := add(destinationTemp, sendr)
    }

    bytes32 senderSigVBytes;

    assembly {
      senderSigVBytes := add(0, v)
    }

    signatures2.push(senderSigVBytes);
    signatures2.push(r);
    signatures2.push(s);

    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 10 ether);
    Assert.equal(instance.tokenBalances(account2, address(coin)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 1 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);

    instance.transfer(
      destinationTemp, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      8 ether,
      feeRecipient,
      fee,  // 1 ether fee
      expiry,
      signatures2);

    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 1 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 8 ether);
    Assert.equal(coin.balanceOf(address(user2)), 1 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(coin)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 1 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
  }
}


contract TestMetaTransactionPool_Shift {
  User user1 = new User();
  User user2 = new User();
  ERC20Token coin = new ERC20Token(address(user1), 100 ether);
  MetaTransactionPool instance = new MetaTransactionPool();

  address recipient;
  address token = address(coin);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp + 7 days;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1() public {
    user1.setToken(address(coin));
    user2.setToken(address(coin));

    sndr = msg.sender;

    Assert.equal(coin.balanceOf(address(user1)), 100 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);

    user1.transfer(msg.sender, 10 ether);

    Assert.equal(coin.balanceOf(address(msg.sender)), 10 ether);

    coin.specialApproval(msg.sender, address(instance), 10 ether);

    Assert.equal(coin.allowance(address(msg.sender), address(instance)), 10 ether);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    // Move and Transfer
    bytes32 destinationTemp = bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  address account2;

  function check_a4_nickpayClaim_useAccount2(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    account2 = msg.sender;

    uint8 _senderSigV = senderSigV;

    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(coin.balanceOf(address(sndr)), 10 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 0 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 10 ether);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 10 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(coin)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 1 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
  }

  // account 2 sends to account 3
  function check_a5_buildNewTransfer_useAccount3() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        false,
        false,
        token,
        8 ether, // the balance of account 2
        feeRecipient,
        fee,  // 1 ether fee
        expiry))
      ));

    Account.sign(2, releaseHash);
  }

  bytes32[] signatures2;

  function check_a6_attemptMoveTransfer_useAccount3(uint8 v, bytes32 r, bytes32 s) public {
    // MOVE destination
    bytes32 destinationTemp = bytes32(uint256(0x0300000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    address sendr = msg.sender;

    assembly {
        destinationTemp := add(destinationTemp, sendr)
    }

    bytes32 senderSigVBytes;

    assembly {
      senderSigVBytes := add(0, v)
    }

    signatures2.push(senderSigVBytes);
    signatures2.push(r);
    signatures2.push(s);

    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 10 ether);
    Assert.equal(instance.tokenBalances(account2, address(coin)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 1 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);

    instance.transfer(
      destinationTemp, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      8 ether,
      feeRecipient,
      fee,  // 1 ether fee
      expiry,
      signatures2);

    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 10 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(coin)), 8 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 2 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
  }
}


contract TestMetaTransactionPool_Claim_invalidExpiry {
  User user1 = new User();
  User user2 = new User();
  ERC20Token coin = new ERC20Token(address(user1), 100 ether);
  MetaTransactionPool instance = new MetaTransactionPool();

  address recipient;
  address token = address(coin);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2_increaseTime86400() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1() public {
    user1.setToken(address(coin));
    user2.setToken(address(coin));

    sndr = msg.sender;

    Assert.equal(coin.balanceOf(address(user1)), 100 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);

    user1.transfer(msg.sender, 10 ether);

    Assert.equal(coin.balanceOf(address(msg.sender)), 10 ether);

    coin.specialApproval(msg.sender, address(instance), 10 ether);

    Assert.equal(coin.allowance(address(msg.sender), address(instance)), 10 ether);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    bytes32 destinationTemp = bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  function check_a4_nickpayClaim_useAccount2_shouldThrow(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    uint8 _senderSigV = senderSigV;

    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(coin.balanceOf(address(sndr)), 10 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 0 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 10 ether);
    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), false);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), true);
    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 10 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(coin)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 1 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
  }
}


contract TestMetaTransactionPool_Claim_invalidSenderSignature {
  User user1 = new User();
  User user2 = new User();
  ERC20Token coin = new ERC20Token(address(user1), 100 ether);
  MetaTransactionPool instance = new MetaTransactionPool();

  address recipient;
  address token = address(coin);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2_increaseTime86400() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1() public {
    user1.setToken(address(coin));
    user2.setToken(address(coin));

    sndr = msg.sender;

    Assert.equal(coin.balanceOf(address(user1)), 100 ether);
    Assert.equal(coin.balanceOf(address(user2)), 0 ether);

    user1.transfer(msg.sender, 10 ether);

    Assert.equal(coin.balanceOf(address(msg.sender)), 10 ether);

    coin.specialApproval(msg.sender, address(instance), 10 ether);

    Assert.equal(coin.allowance(address(msg.sender), address(instance)), 10 ether);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    bytes32 destinationTemp = bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  function check_a4_nickpayClaim_useAccount2_shouldThrow(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    uint8 _senderSigV = senderSigV;

    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(bytes32(0));
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(coin.balanceOf(address(sndr)), 10 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 0 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 10 ether);
    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), false);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), true);
    Assert.equal(coin.balanceOf(address(sndr)), 0 ether);
    Assert.equal(coin.balanceOf(address(msg.sender)), 0 ether);
    Assert.equal(coin.balanceOf(address(instance)), 10 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(coin)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(coin)), 1 ether);
    Assert.equal(coin.allowance(address(sndr), address(instance)), 0 ether);
  }
}

contract MetaTransactionPoolSpecial is MetaTransactionPool {
  function specialDeposit(address sendr) payable public {
    tokenBalances[sendr][address(0)] = msg.value;
  }
}

contract TestMetaTransactionPool_Claim_Ether {
  User user1 = new User();
  User user2 = new User();
  MetaTransactionPoolSpecial instance = new MetaTransactionPoolSpecial();

  address recipient;
  address token = address(0);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp + 7 days;
  bytes32 releaseHash;

  // 10 ether value
  function check_a0_secondAccount_useAccount2() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1_useValue10000000000000000000() public payable {
    sndr = msg.sender;

    instance.specialDeposit.value(10 ether)(msg.sender);

    Assert.equal(address(instance).balance, 10 ether);
    Assert.equal(msg.value, 10 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(0)), 10 ether);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    bytes32 destinationTemp = bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  function check_a4_nickpayClaim_useAccount2(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    uint8 _senderSigV = senderSigV;
    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), false);
    Assert.equal(instance.tokenBalances(msg.sender, address(token)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(token)), 0 ether);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(instance.tokenBalances(msg.sender, address(token)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(token)), 1 ether);
  }
}

contract TestMetaTransactionPool_ClaimAndMove_Ether {
  User user1 = new User();
  User user2 = new User();
  MetaTransactionPoolSpecial instance = new MetaTransactionPoolSpecial();

  address recipient;
  address token = address(0);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp + 7 days;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;


  function check_a1_checkSetup_useAccount1_useValue10000000000000000000() public payable {
    sndr = msg.sender;

    instance.specialDeposit.value(10 ether)(msg.sender);

    Assert.equal(address(instance).balance, 10 ether);
    Assert.equal(msg.value, 10 ether);
    Assert.equal(instance.tokenBalances(msg.sender, address(0)), 10 ether);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    // Move and Transfer
    bytes32 destinationTemp = bytes32(uint256(0x0100000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = address(user1);

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  function check_a4_nickpayClaim_useAccount2(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    uint8 _senderSigV = senderSigV;
    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(address(instance).balance, 10 ether);
    Assert.equal(address(user1).balance, 0 ether);
    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), false);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(instance.invalidatedHashes(sndr, releaseHash), true);
    Assert.equal(address(instance).balance, 0 ether);
    Assert.equal(address(user1).balance, 9 ether);
    Assert.equal(address(user2).balance, 1 ether);
  }
}


contract TestMetaTransactionPool_Move_Ether {
  User user1 = new User();
  User user2 = new User();
  MetaTransactionPoolSpecial instance = new MetaTransactionPoolSpecial();

  address recipient;
  address token = address(0);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp + 7 days;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1_useValue10000000000000000000() public payable {
    sndr = msg.sender;

    instance.specialDeposit.value(10 ether)(msg.sender);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    // Move and Transfer
    bytes32 destinationTemp = bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  address account2;

  function check_a4_nickpayClaim_useAccount2(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    account2 = msg.sender;

    uint8 _senderSigV = senderSigV;

    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(instance.tokenBalances(address(msg.sender), address(0)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(0)), 0 ether);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(instance.tokenBalances(address(msg.sender), address(0)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(0)), 1 ether);
  }

  // account 2 sends to account 3
  function check_a5_buildNewTransfer_useAccount3() public {
    recipient = address(user1);
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(keccak256("new nonce")),
        false,
        false,
        token,
        8 ether, // the balance of account 2
        feeRecipient,
        fee,  // 1 ether fee
        expiry))
      ));

    Account.sign(2, releaseHash);
  }

  bytes32[] signatures2;

  function check_a6_attemptMoveTransfer_useAccount3(uint8 v, bytes32 r, bytes32 s) public {
    // MOVE destination
    bytes32 destinationTemp = bytes32(uint256(0x0200000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(keccak256("new nonce"))) >> 8));
    address sendr = address(user1);

    assembly {
        destinationTemp := add(destinationTemp, sendr)
    }

    bytes32 senderSigVBytes;

    assembly {
      senderSigVBytes := add(0, v)
    }

    signatures2.push(senderSigVBytes);
    signatures2.push(r);
    signatures2.push(s);

    Assert.equal(address(user1).balance, 0 ether);
    Assert.equal(address(user2).balance, 0 ether);
    Assert.equal(instance.tokenBalances(address(account2), address(0)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(0)), 1 ether);

    instance.transfer(
      destinationTemp, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      8 ether,
      feeRecipient,
      fee,  // 1 ether fee
      expiry,
      signatures2);

    Assert.equal(instance.tokenBalances(address(account2), address(0)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user1), address(0)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(0)), 1 ether);

    Assert.equal(address(user1).balance, 8 ether);
    Assert.equal(address(user2).balance, 1 ether);
  }
}


contract TestMetaTransactionPool_Shift_Ether {
  User user1 = new User();
  User user2 = new User();
  MetaTransactionPoolSpecial instance = new MetaTransactionPoolSpecial();

  address recipient;
  address token = address(0);
  uint256 amount = 9 ether;
  address payable feeRecipient = address(user2);
  uint256 fee = 1 ether;
  bytes32 nonce = keccak256("hello world");
  uint256 expiry = block.timestamp + 7 days;
  bytes32 releaseHash;

  function check_a0_secondAccount_useAccount2() public {
    recipient = msg.sender;
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(nonce),
        true,
        true,
        token,
        amount,
        feeRecipient,
        fee,
        expiry))
      ));
  }

  address sndr;

  function check_a1_checkSetup_useAccount1_useValue10000000000000000000() public payable {
    sndr = msg.sender;

    instance.specialDeposit.value(10 ether)(msg.sender);

    Account.sign(1, releaseHash);
  }

  uint8 senderSigV;
  bytes32 senderSigR;
  bytes32 senderSigS;

  function check_a2_useSignature_useAccount1(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(releaseHash, v, r, s));

    senderSigV = v;
    senderSigR = r;
    senderSigS = s;
  }

  bytes32 destination;

  function check_a3_buildSecondSignature_useAccount2() public {
    // Move and Transfer
    bytes32 destinationTemp = bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(nonce)) >> 8));
    bytes32 result;
    address sendr = msg.sender;

    // CLAIM destination

    assembly {
        result := add(destinationTemp, sendr)
    }

    destination = result;

    Account.sign(2, destination);
  }

  bytes32[] signatures;

  address account2;

  function check_a4_nickpayClaim_useAccount2(uint8 v, bytes32 r, bytes32 s) public {
    Assert.equal(msg.sender, ecrecover(destination, v, r, s));

    account2 = msg.sender;

    uint8 _senderSigV = senderSigV;

    bytes32 senderSigVBytes;
    bytes32 recipientSigVBytes;

    assembly {
      senderSigVBytes := add(0, _senderSigV)
      recipientSigVBytes := add(0, v)
    }

    signatures.push(senderSigVBytes);
    signatures.push(senderSigR);
    signatures.push(senderSigS);

    signatures.push(recipientSigVBytes);
    signatures.push(r);
    signatures.push(s);

    Assert.equal(instance.tokenBalances(msg.sender, address(0)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(0)), 0 ether);

    instance.transfer(
      destination, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      amount,
      feeRecipient,
      fee,
      expiry,
      signatures);

    Assert.equal(instance.tokenBalances(msg.sender, address(0)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(0)), 1 ether);
  }

  // account 2 sends to account 3
  function check_a5_buildNewTransfer_useAccount3() public {
    recipient = address(user1);
    releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      instance.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
        instance.SIGNEDTRANSFER_TYPEHASH(),
        recipient,
        bytes11(keccak256("new nonce")),
        false,
        false,
        token,
        8 ether, // the balance of account 2
        feeRecipient,
        fee,  // 1 ether fee
        expiry))
      ));

    Account.sign(2, releaseHash);
  }

  bytes32[] signatures2;

  function check_a6_attemptMoveTransfer_useAccount3(uint8 v, bytes32 r, bytes32 s) public {
    // MOVE destination
    bytes32 destinationTemp = bytes32(uint256(0x0300000000000000000000000000000000000000000000000000000000000000)
      + uint256(bytes32(bytes11(keccak256("new nonce"))) >> 8));
    address sendr = address(user1);

    assembly {
        destinationTemp := add(destinationTemp, sendr)
    }

    bytes32 senderSigVBytes;

    assembly {
      senderSigVBytes := add(0, v)
    }

    signatures2.push(senderSigVBytes);
    signatures2.push(r);
    signatures2.push(s);

    Assert.equal(instance.tokenBalances(account2, address(0)), 9 ether);
    Assert.equal(instance.tokenBalances(address(user1), address(0)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(0)), 1 ether);

    instance.transfer(
      destinationTemp, // 0x00 or 01 or 02 ... 0000 ... address
      token,
      8 ether,
      feeRecipient,
      fee,  // 1 ether fee
      expiry,
      signatures2);

    Assert.equal(instance.tokenBalances(account2, address(0)), 0 ether);
    Assert.equal(instance.tokenBalances(address(user1), address(0)), 8 ether);
    Assert.equal(instance.tokenBalances(address(user2), address(0)), 2 ether);
  }
}
