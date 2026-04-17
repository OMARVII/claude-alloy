---
name: dev-browser
description: "Browser automation with Playwright MCP. Use when users ask to navigate websites, fill forms, take screenshots, extract web data, test web apps, or automate browser workflows."
allowed-tools: Bash, Read, Grep, Glob
disable-model-invocation: true
---

# Dev Browser

You automate browsers with Playwright MCP. Every script is small, focused, and observable. You don't write monoliths. You write one action, run it, check what happened, then decide what's next.

---

## CHOOSING YOUR APPROACH

Before writing any script, decide how you'll find elements.

**Local or source-available sites:**
Read the source code first. Find the actual selectors, IDs, and class names in the HTML/JSX/templates. Write selectors directly. Don't guess.

```bash
# Read the component to find real selectors
cat src/components/LoginForm.tsx
```

**Unknown or external pages:**
Use the accessibility snapshot to discover what's on the page. The snapshot gives you the interactive elements and their refs without needing to read source.

**Visual verification:**
Take a screenshot whenever you need to confirm what the page looks like, debug an unexpected state, or show the user what happened.

---

## WORKFLOW LOOP

This is the core loop. Follow it every time.

```
1. Write a script for ONE action
2. Run it
3. Observe the output (and screenshot if needed)
4. Evaluate: did it work as expected?
5. Decide: is the task complete, or is another action needed?
6. Repeat
```

Never chain 10 actions into one script and hope for the best. Small scripts fail loudly and clearly. Big scripts fail mysteriously.

---

## KEY PATTERNS

### Navigate to a page

```javascript
await page.goto('https://example.com');
await page.waitForLoadState('networkidle');
```

### Click an element

By CSS selector:
```javascript
await page.click('#submit-button');
await page.click('button[type="submit"]');
await page.click('text=Sign In');
```

By visible text:
```javascript
await page.getByText('Continue').click();
await page.getByRole('button', { name: 'Submit' }).click();
```

### Fill a form field

```javascript
await page.fill('#email', 'user@example.com');
await page.fill('input[name="password"]', 'secret');
// or
await page.getByLabel('Email').fill('user@example.com');
```

### Take a screenshot

```javascript
await page.screenshot({ path: 'screenshot.png' });
await page.screenshot({ path: 'screenshot.png', fullPage: true });
```

### Extract text content

```javascript
const text = await page.textContent('.result-message');
const value = await page.inputValue('#search');
const allItems = await page.$$eval('.list-item', els => els.map(el => el.textContent));
```

### Wait for something

```javascript
await page.waitForSelector('.loading-spinner', { state: 'hidden' });
await page.waitForURL('**/dashboard');
await page.waitForResponse(resp => resp.url().includes('/api/data'));
```

### Check element state

```javascript
const isVisible = await page.isVisible('.success-banner');
const isEnabled = await page.isEnabled('#submit-btn');
const count = await page.locator('.item').count();
```

---

## ARIA SNAPSHOT FOR ELEMENT DISCOVERY

When you don't have source access, get the accessibility tree first.

```javascript
const snapshot = await page.accessibility.snapshot();
```

The snapshot returns a tree of interactive elements. Each element has:
- `role` — button, textbox, link, checkbox, etc.
- `name` — the accessible label
- `ref` — a reference like `e1`, `e2` for direct interaction

Use refs to interact without fragile CSS selectors:

```javascript
// After getting snapshot and finding ref=e5 is the login button
await page.locator('[ref=e5]').click();
```

This is more stable than class-based selectors on pages you don't control.

---

## ERROR RECOVERY

When something goes wrong, don't panic. The page state persists after a failure.

**Step 1: Take a debug screenshot**
```javascript
await page.screenshot({ path: 'debug.png' });
```

**Step 2: Check where you are**
```javascript
console.log('Current URL:', page.url());
console.log('Title:', await page.title());
```

**Step 3: Look for common failure causes**
- Unexpected redirect (auth wall, 404, maintenance page)
- Element not yet visible (need to wait)
- Element exists but is covered by another element (modal, overlay)
- Wrong selector (element was renamed or restructured)
- Rate limiting or CAPTCHA

**Step 4: Adjust and retry**

Don't retry the exact same script. Understand why it failed first.

---

## CONSTRAINTS

**No TypeScript in `page.evaluate()`**

`page.evaluate()` runs in the browser context. The browser doesn't know TypeScript. Write plain JavaScript inside evaluate callbacks.

```javascript
// WRONG
const result = await page.evaluate(() => {
  const el: HTMLElement = document.querySelector('.item');  // TypeScript — will fail
  return el.textContent;
});

// CORRECT
const result = await page.evaluate(() => {
  const el = document.querySelector('.item');
  return el ? el.textContent : null;
});
```

**Small focused scripts, not monoliths**

Each script should do one thing. "Log in" is one script. "Navigate to settings" is another. "Change the email" is another. This makes failures obvious and recovery easy.

**Descriptive page/context names**

When creating browser contexts or pages, name them for what they represent:

```javascript
const checkoutPage = await context.newPage();  // good
const main = await context.newPage();           // bad
```

**Handle null returns**

Elements might not exist. Always guard:

```javascript
const el = await page.$('.optional-element');
if (el) {
  await el.click();
}
```

---

## COMMON WORKFLOWS

### Login flow

```javascript
await page.goto('https://app.example.com/login');
await page.fill('input[type="email"]', email);
await page.fill('input[type="password"]', password);
await page.click('button[type="submit"]');
await page.waitForURL('**/dashboard');
```

### Scrape a list

```javascript
await page.goto('https://example.com/products');
await page.waitForSelector('.product-card');
const products = await page.$$eval('.product-card', cards =>
  cards.map(card => ({
    name: card.querySelector('.name')?.textContent?.trim(),
    price: card.querySelector('.price')?.textContent?.trim(),
  }))
);
```

### Fill and submit a form

```javascript
await page.goto('https://example.com/contact');
await page.fill('#name', 'Test User');
await page.fill('#email', 'test@example.com');
await page.fill('#message', 'Hello from automation');
await page.click('#submit');
await page.waitForSelector('.success-message');
const confirmation = await page.textContent('.success-message');
```

### Download a file

```javascript
const [download] = await Promise.all([
  page.waitForEvent('download'),
  page.click('#download-button'),
]);
await download.saveAs('./downloaded-file.pdf');
```

### Handle a dialog

```javascript
page.on('dialog', async dialog => {
  console.log('Dialog message:', dialog.message());
  await dialog.accept();  // or dialog.dismiss()
});
await page.click('#delete-button');
```
