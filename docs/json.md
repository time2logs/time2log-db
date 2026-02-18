```json
{
  "version": "2026.1", 
  "profession": { "key": "maurer", "label": "Maurer/in EFZ" },
  "competencies": [
    { "code": "A1", "description": "Kann eine Mauer bauen." },
    { "code": "B4", "description": "Kann Arbeitssicherheit anwenden." }
  ],
  "nodes": [
    {
      "key": "baugrundlagen",
      "label": "Baugrundlagen",
      "type": "category",
      "children": [
        {
            "key": "mauern",
            "label": "Mauern",
            "type": "category",
            "children": [
                {
                    "key": "mauer-bauen",
                    "label": "Mauer bauen",
                    "type": "activity",
                    "competencies": ["A1", "B4"]
                }
            ]
        }
      ]
    }
  ]
}
```