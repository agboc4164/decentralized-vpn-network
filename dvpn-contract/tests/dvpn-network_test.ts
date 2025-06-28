import {
  Clarinet,
  Tx,
  Chain,
  Account,
  types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "Node management - toggle status test",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const nodeOwner = accounts.get('wallet_1')!;
    
    // First register a node
    let block = chain.mineBlock([
      Tx.contractCall('dvpn-network', 'register-node', [
        types.ascii("192.168.1.1"),
        types.ascii("New York, USA"),
        types.uint(100),
        types.uint(50000)
      ], nodeOwner.address)
    ]);
    
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectUint(1);
    
    // Test toggle node status
    let toggleBlock = chain.mineBlock([
      Tx.contractCall('dvpn-network', 'toggle-node-status', [
        types.uint(1)
      ], nodeOwner.address)
    ]);
    
    assertEquals(toggleBlock.receipts.length, 1);
    toggleBlock.receipts[0].result.expectOk().expectBool(false);
  },
});

Clarinet.test({
  name: "Enhanced node performance metrics test",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('dvpn-network', 'get-active-nodes-count', [], deployer.address)
    ]);
    
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectUint(0);
  },
});