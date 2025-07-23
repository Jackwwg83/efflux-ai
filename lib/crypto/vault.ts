/**
 * Client-side encryption for sensitive data like API keys
 * Uses Web Crypto API for secure encryption
 */

export class VaultClient {
  private userId: string
  private key: CryptoKey | null = null
  
  constructor(userId: string) {
    this.userId = userId
  }

  /**
   * Initialize the vault with a user-specific key
   */
  async initialize(): Promise<void> {
    // Derive a key from the user ID (in production, use a more secure method)
    const encoder = new TextEncoder()
    const keyMaterial = await crypto.subtle.importKey(
      'raw',
      encoder.encode(this.userId + '-efflux-vault-key'),
      { name: 'PBKDF2' },
      false,
      ['deriveBits', 'deriveKey']
    )

    // Derive the actual encryption key
    this.key = await crypto.subtle.deriveKey(
      {
        name: 'PBKDF2',
        salt: encoder.encode('efflux-salt-2024'),
        iterations: 100000,
        hash: 'SHA-256'
      },
      keyMaterial,
      { name: 'AES-GCM', length: 256 },
      false,
      ['encrypt', 'decrypt']
    )
  }

  /**
   * Encrypt data
   */
  async encryptData(data: string): Promise<string> {
    if (!this.key) {
      throw new Error('Vault not initialized')
    }

    const encoder = new TextEncoder()
    const iv = crypto.getRandomValues(new Uint8Array(12))
    
    const encrypted = await crypto.subtle.encrypt(
      {
        name: 'AES-GCM',
        iv: iv
      },
      this.key,
      encoder.encode(data)
    )

    // Combine IV and encrypted data
    const combined = new Uint8Array(iv.length + encrypted.byteLength)
    combined.set(iv, 0)
    combined.set(new Uint8Array(encrypted), iv.length)

    // Convert to base64 for storage
    return btoa(String.fromCharCode(...combined))
  }

  /**
   * Decrypt data
   */
  async decryptData(encryptedData: string): Promise<string> {
    if (!this.key) {
      throw new Error('Vault not initialized')
    }

    // Convert from base64
    const combined = Uint8Array.from(atob(encryptedData), c => c.charCodeAt(0))
    
    // Extract IV and encrypted data
    const iv = combined.slice(0, 12)
    const encrypted = combined.slice(12)

    const decrypted = await crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: iv
      },
      this.key,
      encrypted
    )

    const decoder = new TextDecoder()
    return decoder.decode(decrypted)
  }

  /**
   * Generate a hash of the data (for duplicate detection)
   */
  static async hash(data: string): Promise<string> {
    const encoder = new TextEncoder()
    const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(data))
    const hashArray = Array.from(new Uint8Array(hashBuffer))
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('')
  }
}