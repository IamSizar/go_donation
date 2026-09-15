/**
 * chatExport.test.ts — the rows and columns a single-conversation export writes.
 *
 * WHAT IT PINS
 *   - sender_role is a readable, translated word for each chat system:
 *       donor chat     the int stored on the message: 0 is support
 *                      (chat.RoleSupport, backend/internal/chat/chat.go), and a
 *                      participant's app role_id otherwise, 1 donor,
 *                      2 beneficiary, 3 volunteer (handlers/registration.go);
 *       marriage chat  'requester' | 'owner' | 'staff'
 *                      (backend/internal/marriagechat/marriagechat.go);
 *       staff chat     the sender's staff tier.
 *   - sent_at is an ISO-8601 UTC string.
 *   - The body is copied untouched, and survives commas, quotes and line
 *     breaks when written through lib/csv.ts's real downloadCsv.
 *   - The column list is exactly six columns (eight for a group export), and
 *     no contact field is ever copied into a row.
 *   - The filename and title name the chat type and the thread id.
 *
 * English is the default locale (src/test/setup.ts clears localStorage after
 * each test); the Arabic cases set it for one test.
 */
import { describe, expect, it, vi } from 'vitest'
import {
  chatExportColumns,
  chatExportFilenameBase,
  chatExportTitle,
  donorExportRows,
  groupChatExportColumns,
  marriageExportRows,
  staffExportRows,
  toExportRow,
  type DonorChatMessage,
  type MarriageChatMessage,
  type StaffChatMessage,
} from './chatExport'
import { downloadCsv } from './csv'

// ─── Fixtures ───

/** A body with every character CSV has to escape: comma, quote, line break. */
const TRICKY_BODY = 'Two boxes, three bags.\nPick-up at "Gate 2", after 5pm.'

const SIX_COLUMNS = ['message_id', 'sent_at', 'sender_name', 'sender_user_id', 'sender_role', 'body']

/** A donor-chat message with sensible defaults; override what the test is about. */
function donorMessage(overrides: Partial<DonorChatMessage> = {}): DonorChatMessage {
  return {
    id: 7001,
    thread_id: 7,
    sender_user_id: 101,
    sender_role: 1,
    sender_name: 'Layla Hassan',
    body: 'I bought the notebooks.',
    created_at: '2026-09-14T14:50:00Z',
    ...overrides,
  }
}

/** A marriage-chat message with sensible defaults. */
function marriageMessage(overrides: Partial<MarriageChatMessage> = {}): MarriageChatMessage {
  return {
    id: 5101,
    thread_id: 51,
    sender_user_id: 108,
    sender_role: 'requester',
    sender_name: 'Karim Adel',
    body: 'I would like to arrange a family meeting.',
    created_at: '2026-09-12T09:00:00Z',
    ...overrides,
  }
}

/** A staff-chat message with sensible defaults. */
function staffMessage(overrides: Partial<StaffChatMessage> = {}): StaffChatMessage {
  return {
    id: 6101,
    thread_id: 61,
    sender_user_id: 1,
    sender_name: 'Rana Aziz',
    body: 'Morning.',
    created_at: '2026-09-15T08:30:00Z',
    ...overrides,
  }
}

/** Reads a Blob as text through FileReader, which jsdom implements. */
function readBlob(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result))
    reader.onerror = () => reject(reader.error)
    reader.readAsText(blob)
  })
}

// ─── Donor chat ───

describe('donorExportRows', () => {
  it('writes one row per message with the ISO send time, the sender and the body untouched', () => {
    // Arrange
    const message = donorMessage({ body: TRICKY_BODY, created_at: '2026-09-14T17:50:00+03:00' })

    // Act
    const rows = donorExportRows([message])

    // Assert
    expect(rows).toEqual([
      {
        message_id: 7001,
        sent_at: '2026-09-14T14:50:00.000Z',
        sender_name: 'Layla Hassan',
        sender_user_id: 101,
        sender_role: 'Grantor',
        body: TRICKY_BODY,
      },
    ])
  })

  it('names support and every app role in English', () => {
    // Arrange
    const messages = [0, 1, 2, 3].map((role, i) => donorMessage({ id: 7001 + i, sender_role: role }))

    // Act
    const roles = donorExportRows(messages).map((row) => row.sender_role)

    // Assert
    expect(roles).toEqual(['Support', 'Grantor', 'Recipient', 'Volunteer'])
  })

  it('names the same roles in Arabic when the interface is Arabic', () => {
    // Arrange
    localStorage.setItem('locale', 'ar')
    const messages = [0, 1, 2, 3].map((role, i) => donorMessage({ id: 7001 + i, sender_role: role }))

    // Act
    const roles = donorExportRows(messages).map((row) => row.sender_role)

    // Assert
    expect(roles).toEqual(['الدعم', 'مانح', 'مستحق', 'متطوع'])
  })

  it('labels a role id it does not know instead of printing a bare number', () => {
    // Act
    const [row] = donorExportRows([donorMessage({ sender_role: 9 })])

    // Assert
    expect(row.sender_role).toBe('Role 9')
  })

  it('never copies a contact field from the message into the row', () => {
    // Arrange: a message that, somehow, carries the sender's phone.
    const withPhone = { ...donorMessage(), sender_phone: '+9647701002001' } as DonorChatMessage

    // Act
    const [row] = donorExportRows([withPhone])

    // Assert
    expect(Object.keys(row).sort()).toEqual([...SIX_COLUMNS].sort())
  })
})

// ─── Marriage chat ───

describe('marriageExportRows', () => {
  it('names the requester, the owner and staff the way the marriage chat page does', () => {
    // Arrange
    const messages = [
      marriageMessage({ id: 5101, sender_role: 'requester' }),
      marriageMessage({ id: 5102, sender_role: 'owner' }),
      marriageMessage({ id: 5103, sender_role: 'staff' }),
    ]

    // Act
    const roles = marriageExportRows(messages).map((row) => row.sender_role)

    // Assert
    expect(roles).toEqual(['Requester', 'Owner', 'Support'])
  })
})

// ─── Staff chat ───

describe('staffExportRows', () => {
  it("names each sender by their staff tier, and falls back to Staff when the tier isn't known", () => {
    // Arrange
    const messages = [
      staffMessage({ id: 6101, sender_user_id: 1 }),
      staffMessage({ id: 6102, sender_user_id: 2 }),
      staffMessage({ id: 6103, sender_user_id: 3 }),
    ]
    const parties = [
      { user_id: 1, staff_tier: 'super_admin' },
      { user_id: 2, staff_tier: 'admin' },
      { user_id: 3, staff_tier: null },
    ]

    // Act
    const roles = staffExportRows(messages, parties).map((row) => row.sender_role)

    // Assert
    expect(roles).toEqual(['Super Admin', 'Admin', 'Staff'])
  })

  it('leaves the name empty rather than inventing one when the server sent none', () => {
    // Act
    const [row] = staffExportRows([staffMessage({ sender_name: null })], [])

    // Assert
    expect(row.sender_name).toBe('')
  })
})

// ─── sent_at ───

describe('sent_at', () => {
  it('is an ISO-8601 UTC string whatever offset or precision the server sent', () => {
    // Arrange: Go marshals time.Time as RFC 3339 with up to nanoseconds.
    const messages = [
      donorMessage({ created_at: '2026-09-14T14:50:00.123456Z' }),
      donorMessage({ created_at: '2026-09-14T17:50:00+03:00' }),
    ]

    // Act
    const sentAt = donorExportRows(messages).map((row) => row.sent_at)

    // Assert
    expect(sentAt).toEqual(['2026-09-14T14:50:00.123Z', '2026-09-14T14:50:00.000Z'])
  })

  it("keeps a timestamp it can't parse as it arrived, instead of failing the whole export", () => {
    // Act
    const [row] = donorExportRows([donorMessage({ created_at: 'not a date' })])

    // Assert
    expect(row.sent_at).toBe('not a date')
  })
})

// ─── Columns ───

describe('chatExportColumns', () => {
  it('writes exactly the six conversation columns, none of which can carry contact details', () => {
    // Act
    const headers = chatExportColumns().map((column) => column.header)

    // Assert
    expect(headers).toEqual(SIX_COLUMNS)
    expect(headers.join(' ')).not.toMatch(/phone|email|whatsapp|contact|address/)
  })

  it('adds the masked label and the role in the group for a group export', () => {
    // Arrange
    const columns = groupChatExportColumns()
    const row = toExportRow(staffMessage(), 'Staff', { masked_label: 'Donor 1', role_in_group: 'Donor' })

    // Act
    const headers = columns.map((column) => column.header)
    const values = columns.map((column) => column.get(row))

    // Assert
    expect(headers).toEqual([...SIX_COLUMNS, 'masked_label', 'role_in_group'])
    expect(values.slice(-2)).toEqual(['Donor 1', 'Donor'])
  })

  it('keeps commas, quotes and line breaks inside one quoted Body cell, under translated headers', async () => {
    // Arrange: jsdom has no URL.createObjectURL, and clicking the download
    // link would log jsdom's "navigation not implemented". Capture the Blob.
    let blob: Blob | undefined
    URL.createObjectURL = vi.fn((b: Blob) => {
      blob = b
      return 'blob:chat-export'
    })
    URL.revokeObjectURL = vi.fn()
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
    const rows = donorExportRows([
      donorMessage({ id: 7002, sender_user_id: 103, sender_role: 2, sender_name: 'Sara Ali', body: TRICKY_BODY, created_at: '2026-09-14T15:05:00Z' }),
    ])

    // Act
    downloadCsv('donor_chat_7.csv', rows, chatExportColumns())
    const text = await readBlob(blob!)

    // Assert: FileReader decodes UTF-8 and drops the BOM csv.ts writes for
    // Excel, so the text starts at the header row.
    expect(text).toBe(
      'Message ID,Sent at,Sender name,Sender user ID,Sender role,Body\n' +
        '7002,2026-09-14T15:05:00.000Z,Sara Ali,103,Recipient,"Two boxes, three bags.\nPick-up at ""Gate 2"", after 5pm."',
    )
  })
})

// ─── Filename and title ───

describe('chatExportFilenameBase and chatExportTitle', () => {
  it('names the file after the chat type and the thread id, in filename-safe characters', () => {
    // Assert
    expect(chatExportFilenameBase('donor', 7)).toBe('donor_chat_7')
    expect(chatExportFilenameBase('support', 20)).toBe('support_chat_20')
    expect(chatExportFilenameBase('marriage', 51)).toBe('marriage_chat_51')
    expect(chatExportFilenameBase('staff', 61)).toMatch(/^[a-z0-9_]+$/)
  })

  it('titles the document with the translated chat type and the thread id', () => {
    // Assert: English
    expect(chatExportTitle('donor', 7)).toBe('Grantor chat #7')
    expect(chatExportTitle('staff', 61)).toBe('Staff chat #61')

    // Assert: Arabic
    localStorage.setItem('locale', 'ar')
    const arabic = chatExportTitle('marriage', 51)
    expect(arabic).toContain('محادثة زواج')
    expect(arabic).toContain('51')
  })
})
