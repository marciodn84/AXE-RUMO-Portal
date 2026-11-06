create table public.erp_empresas (
 id uuid primary key default gen_random_uuid(),
 razao_social text not null,
 nome_fantasia text,
 cnpj text not null unique check(cnpj ~ '^[0-9]{14}$'),
 inscricao_estadual text,
 endereco text not null,
 endereco_entrega text,
 email text,
 telefone text,
 logo text,
 logo_padrao boolean not null default false,
 ativa boolean not null default true,
 versao integer not null default 1,
 atualizado_por uuid,
 atualizado_em timestamptz not null default now()
);
alter table public.erp_empresas enable row level security;
revoke all on public.erp_empresas from public,anon,authenticated;
grant select,insert,update on public.erp_empresas to service_role;

insert into public.erp_empresas(razao_social,nome_fantasia,cnpj,inscricao_estadual,endereco,endereco_entrega,email,logo,logo_padrao)
values('AXE ENGENHARIA E SISTEMAS LTDA','AXE Engenharia','39893713000167','9087109248',
 'Rua Esper Jorge Chueri · Cajuru · Curitiba – PR · 82930-220 · Brasil',
 'Rua Esper Jorge Chueri · Cajuru · Curitiba – PR · 82930-220 · Brasil','marcio@axeengenharia.com.br','data:image/jpeg;base64,/9j/4AAQSkZJRgABAgAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCACWAVEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKQkKpZiABySe1LXn/AMStVu7z7D4J0eQrqmuEpNIv/Lvaj/WSH6jIHrz3oAfdfGXwTbXUkA1OW4MbbWe3tZJEz7MBg/hUP/C7PBX/AD9Xv/gDL/8AE1xXiT4lS+DNQTw14Rgs007TYxbs0ke4vIPvcgj6E9zmsf8A4Xh4u/u6d/34P/xVaqjJq5m6kUem/wDC7PBX/P1e/wDgDL/8TR/wuzwV/wA/V7/4Ay//ABNaHw21vX/Efh5tW1sW6LO+LZIoinyDgsck9TwPp71wPjH4k+NvCPiS40ydbBowd8EptyPMjPQ/e/A+4NSqbb5UU5pK513/AAuzwV/z9Xv/AIAy/wDxNaGi/FXwhruqRaba6k8d3McRJcQPF5h9AWABPtXkX/C8PF393Tv+/B/+Krb0bxK/xZ0vUfDOufZoNV2faNLuYkKFJV545JBGB06jd6VUqMoq7Eqibse60Vyfw+8Ty+JfDmL9PK1iwkNpqMJ4KTLwTj0br+Y7V1lZFhRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAVNT1K10fS7rUb2URWttG0srnsoGfzrxj+3LnRPDWqfEDUl8vxB4j/c6XC3W2th9zH4YY+p2+prpvGcv/AAmvjG18FQyY0qxC3+uSg4Gwcxwk+/U+2D2rx74h+K/+Er8TyTQHbp1qPIs0AwAg/ix79fpgdq1pQ5pETlZHKMxdizEsxOSSckmtbwxoM/ibxHZaTBkGeTDuB9xByzfgM1kV798D/Cv2HSJvENzHie9/d2+RysQPJ/4ER+Sj1rqqS5Y3MIR5nY9UsrODT7GCztYxHBBGscaDsoGAK434o+DB4s8NtJbRg6nZAyW+By4/iT8cce4FdlcXltaNCLmeOIzyCKIOwG9znCj1PBqeuJNp3OlpNWPiYggkEYI6g1a03UbnSdTttQs5PLuLeQSRt7j+lejfGTwX/YmtDXLKLFhfufMCjiKbqfwbk/XNeX13xkpK5ytOLse7ya7b6VrOlfEnT/k0bWFSy1yIdIZOiSn/AHTwT6f71ewqwZQykEEZBHevmn4X63aNPeeEdZ+fSNaQxYY8JKRgEehPAz6hfSvV/hrqt3aC+8FaxIW1TQyEikb/AJeLU/6uQfQYB9OO9cNSHLKx0wlzI9AoooqCgooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigArB8ZeJoPCPhi71aZfMkQbLeHvNK3CIPqf0BrerzbxME1D4z+GNN1VsabDaS3llG33ZrtTjB9Sq/MP8A69AHEeJLmfwN4DOkzzb/ABP4jY3mrTZ+ZFbqv0/hHb7/AK15NW/42vdS1Dxlqk2rIY7wTsjRZyIwOFUewGOe/XvWBXfTjyxOWcrs2fCfh+bxR4lstJhyBM+ZXH8EY5Zvy/XFfW8cdppOmrGuy3s7WIAZOFjRR/IAV5j8EfCv9naHLr9zHi5v/lhyOVhB6/8AAiM/QCsX4zePfMd/C2mS/Ip/06RT1PaP8Op/AetYTvUnyo0j7kbs4z4heO7jxX4kWe0lkisLJsWYBIOQf9Z7McD6ACvc/hx40j8Y+HVkmZRqVtiO6QcZPZwPRv55FfK9b/g3xTc+EPEUGpwZaL7lxED/AKyM9R9e49wK1nSTjZdCIzad2fVOvaLaeItEutKvVzDcJtz3U9mHuDg18ka7ot34e1u60u9XbPbvtJxww7MPYjB/Gvr/AE+/ttU0+3v7OUS21wgkjcdwa83+Mvgv+2tGGu2UWb6wQ+aFHMkPU/ivJ+mfasKM+V2ZrUjdXR88KzIwZWKsDkEHBBr2c67c634b0v4g6avma/4d/capCvW5tj9/P4ZYeh3eleL16B8HbvUYvHMdpaRCa1uomS8jb7vlAfeP0OPzx3retHmiZU5WZ9H6bqNrq+mW2o2UoltbmNZYnHdSM/nVqvN/hKRb/wDCT6XYyNLodhqjx6fITkAHl0U9wpP616RXEdIUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAVyfxB8MTeJfDudPfytZsJBd6dMOCsy8gZ9G6fke1dZRQB87eO7eLxl4SsfHljB5d0gFrq1uBzFKvGSPY8c9itcX4Q8Oy+KfFFlpUeQkj7pnH8EY5Y/lwPcivatas4PB3j6SW5jB8L+Lf9GvkP3IbsggMfQOM598nsKd4Y8NWXwo0nXdb1aVXPmFIGBG54QfkUf7THqPYeldEKtoW6mUoe9c1PiL4xt/AvhmKx04Il/NH5NpEvSFAMb8eg6D1P0NfMskjyyNJI7O7kszMckk9STWn4j8QXnifXbjVb5v3sx+VAfljUdFHsP/r1lVvThyLzMpy5mOaN0Cl0ZQwypIxkeoptdB4d8SRaZ/oWq2Mep6PI2ZLaT7yHu8bdUb6Hnv6jubz4S2evaWus+CNVW6tpORa3Jwynuu7sR6MB9abmovUFG+w74MeOP7Ovv+Ea1CXFpcvm0ZjxHKf4fo38/rXvpAYEEAg8EGvjbU9I1TQb37PqNncWdwpyBIpXPup6H6ivpH4YeNl8XeHxFdOP7UswEuATzIO0n49/f6iuetD7SNacvss8X+KHgw+E/EjPbRkaZekyW5A4Q/xJ+GePYium0mwu/BngS2tbBP8AirvFjiC0Xo1vCern0wp3E9iR/dr2TxHo+kaxpe3Wo0a0tXF0Wc4CbOSSfTGQfYmuO8AwS+K/EN98QL6NlhmBtNGhcY8u2U4L47Fzn9exqJVXKPKNQSlc7Hwx4etPC3hyy0ayH7q2j2l8YMjdWY+5OTWvRRWRoFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFAGR4o8PWnirw5e6Nej91cx4V8ZMbjlWHuDg15Bq8WpeM/hzc6bfPJ/wk3hSYpeQBs+egGBJjvlRkH2b1r3avNvHsEvhPxHY/ECxjZoIwLPWYUGfMtmOBJjuUOP07CnF8ruhNXVj5vor0Xxt8ONSi8QyXPhzTp77SL1Rc272qF1QNzt47ensRXOf8ID4t/6F3Uv+/DV3qcWr3OVxaOdrofCPjHVPB2pi6sJN0LkCe2c/JKPf0Poe36Uv/CA+Lf8AoXdS/wC/DUf8ID4t/wChd1L/AL8NQ3FqzBJo+j9H1fw58RvD+/yIbqLpNa3CgvC3oR29iK5xfhc3hvX4td8IXhhljP7yxuWJjlQ/eQP1Ge2c84PavJ9B0Hx/4a1SPUNL0XU4Zl4I8hirr3Vh3Fe8R+NBa+CbrxDrmm3WlvZxkz2867Sz4GAhPUMSAPc1yzTh8L0N4vm3Wph/EC8uPEurad4A052jkvwLjVZEPNvaKeVz6seP/rGvQbS0gsbOG0tYlit4EWOONeiqBgAfhXGfDXQ7yDT7vxLrS/8AE811xczgjmGL/lnEPQBccfh2ruaxNAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACobu0gv7Oa0uollt50MckbDhlIwQfwqaigDzeD4ZazpcQs9E8e6tY6dGT5Fs8STeUv8AdDHBwO1S/wDCBeLv+il6n/4Bx/416HRQB55/wgXi7/opep/+Acf+NH/CBeLv+il6n/4Bx/416HRQB55/wgXi7/opep/+Acf+NLF8Mru9vLaTxN4t1HXLS2lEyWUsaxRM46FwPvAelehUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABXjvxB+N0vg3xbPolrpEN4II0MkjzlSGYbsYAPYivYSQASTgDqa+VvBsMPj748zXl3DHcWb3M908cihlMaghAQeo+4KAPVPhp8YpPHniGfSbrS4rJ1tzNGyTF95BAI5A7HP4V6Xqct7DpdzLp0EdxeJGWhhkfasjDopPbPTNfMqiPwH+0cEiRbezN+FCqMKsU69APQb/0r6loA8i8B/Gz/hKPFf8AYGraUmmTyBlhPmlsyr1RgQMHAP4jHeuu+Ivjy18A+HhfyRLcXcziO2ti23zD3JPYAd/oO9eRfHXwVNoetweNdGDRJLKpuTHwYZwcrIPTdj/voe9cfJe698a/H+n20wEX7tYyI+UgjUDzJPqTk/UgelAH0F8NPG2reO9MuNUvNIh0+xV/LgZZS5lYfePIHA4GfXPpXD+Kvj5e+HfFWp6OmgW86Wc7RCRrgqWA74217NpWl2mi6Ta6ZYRCK1tYxHGg7AevqT1J9a+WdTWyb9oicaiIDZHWf332jHl7d3O7PGPrQB1H/DS1/wD9C1bf+BTf/E113w4+Ml1468UnR5tGhtE+zvN5iTlzlSOMED1rpPsvwt/ueEfzt609Cg8EpqBbw+mgi9CHJsPK8zZxn7nOOlAHS1yvxD8XS+CPCcmtQ2iXbpKkflO5UHccZyAa6qvMfj5/yS24/wCvqH/0KgDg/wDhpa//AOhatv8AwKb/AOJo/wCGlr//AKFq2/8AApv/AImrnwVh8FSeB5m8QroJvPtsmPt/leZs2pj7/OM5/WvRvs3wt/ueEfzt6AM3W/ihcaT8LNK8YLpcUkt86K1sZSFTcG/ixz93071wtt+0ldvdQLc+HII4HcB3FyxIXPJHy84rovjqlgnwksl0wW4sRfReSLbHl7dr/d28Y+lecatof279nXw/rEaZk0+9nVyB/wAs5JGB/wDHgn50AfU/mK0XmIQyldwI7ivLfhv8W7rx34nutIm0iG0WC2eYSJMXJIdVxggf3v0rf+Fuu/8ACQfDLSbpm3TQwfZpfXdH8vP1AB/GvGf2ev8AkpOqf9g+X/0bHQB658RfirpfgDyrVoGvtTmXetsj7Qi9mdsHGewxk4rzT/hpa/8A+hatv/Apv/ia57TrKL4h/tA3MWpgy2jXszOhP3oogQqfQhVFfRg8DeEwAB4a0jAGB/ocf+FAHn3w8+NF3438WRaLNosNojxPJ5qTliNozjBAp/xG+Mt14G8VHR4dGhu0ECS+Y85Q/NnjAB9K9IsPDGgaXdC60/RdPtLgAqJYLZEYA9RkDNfNfx7x/wALUXdjH2SDOfqaAN//AIaWv/8AoWrb/wACm/8Aia2PCnx8vfEfirTdGk0G3gS8nWIyrcFiue+Ntdytr8LtozH4Szj1t6t6bbfD0alAdLTw19uDZh+zeR5m7/Z285+lAHF+P/jXeeDPGFxocOiQ3axJGwlacqTuUHoAfWr/AMM/i+/jzXrrSrrTIrGWOAzRlJS+/BAYcgeoP515n8Tf+ThbT/r5sf8A2SrOvf8AFAftHQX4/d2d5cLMT0HlzZWQ/gxY/hQB7L8SvGs3gPwzHq0Nkl4z3KweW8hQAEMc5AP92oNG8ezap8KJ/GbWEccsVvcTfZhISp8ssAN2O+3071zv7RH/ACTmD/sIR/8AoD1R8Jf8mvXv/YPvv/QpKAN/4W/E+4+IdxqcU+lxWQs0jYFJS+7cW9QMfdr0G/uTZ6fc3QUMYYmkCk4zgE4/SvnX9nbVtN0q98QNqOoWlmJI4AhuJlj3YL5xuIzXtmseLPDkmiX6J4g0pna2kCqL2MknafegDkfhj8W7rx/r11ps+kQ2awWxnDpMXJIZVxggf3q7fxl4jTwl4S1DXGiEptYwUjZtodiQqjP1IrwH9nD/AJHjU/8AsHN/6MSu1/aN1j7L4Q07SkbD3t1vYZ6pGP8A4pl/KgDm/wDhpa//AOhatv8AwKb/AOJr3nQNXj17w9p+rQjal5bpNtznaWGSPwOR+FfPOpeB7WD9nCy1dbKEaksq3klwIx5hjdyoXd1I2spx7V6L8AtZ/tL4bpaO+ZNPuHgweu0/Ov8A6ER+FAFP4i/Ga78D+K20aHRobtFhSXzXnKn5s8YAPpXJ/wDDS1//ANC1bf8AgU3/AMTWB8dwG+LIBAINtACD+NfRK+B/Cm0Z8NaRnH/PlH/hQBxXw9+Ndj4z1hdHvdPOnX8oJgIl3xykDJGcAg4BPvioviT8YrrwH4nj0iHR4bxWtkn8x5yhySwxgA/3a8sNnZaZ+0fb2mlRxw2kWsRKkcX3Vzt3AegyWGO1T/tEf8lIg/7B0X/oclAH1HC/mwxyYxuUNj6ivFPGHx8n8OeLNR0a00SC6is5fK857gqWYAbuAOxyPwr2F7uOw0VryY4igt/Nc+iquT/Kvmb4NaTD4y+JuoajqtrDdwpFNdSxzoHRpHbAyDx/ET+FAHrnwu+KjfEK61G1uNOjsprVEkQJKX3qSQeoGMHH516VXy78PHPg34+z6Sx2QyXE9jjoCpJMf5lU/OvqKgAooooA5n4h6x/YPw/1vUA210tWSM/7b/Iv6sK+ZPhX4703wDq99qF9YXF3JPAIYvJKjaN2Wzn1wtet/tGaz9k8IafpKsA99db2GeqRjJ/8eZfyp/wX8C6Hc/Dm2v8AVtGsby4vJpJVe5t1dggO0AEjp8pP40AeM/EvxnYeNPFUOt6baXFm6wJHIJSpJdScMMexA/CvrXw1qq674Y0vVVIP2u1jlOOzFRkfnmvIPjv4K0bTvBNvqekaTZ2UlvdqsrW0CxlkYEc4H97b+dL8NPiHaeHvgjc3l64eXSp3t4YSeZWf541H4sfoFPpQA39oHx0LayTwfYSAzXAWW+I52JnKp9SQCfYD1rznwTrGqfCbx7anWrSS3t7uBBdRsMnyXwQ491Pb2Irb+EnhW7+IHji68V67me1tp/OlZxxNOeVXHovBI9No6GvU/jR4D/4S3wsb+yi3atpqmSLaOZY+rp7+o9xjvQB6TFLHPCk0Tq8UihkdTkMDyCD6V8h+KtGPiH45ajo4n8g3mqGHzSu7Zk4zjjNeo/ALx7/aGnHwnqM2bq0UvZMx5eLun1Xt7f7tch8YfCmueGfiA/i7S4pjaTSpdR3MS7hBMuMhvTkZGeDnHY0AbX/DM83/AENCf+AR/wDi6634c/ByTwH4lfV21pbwNbPB5Qt9n3ipzncf7teap+0Z4tWNVaw0h2AwWMUgz/4/XbfC/wCL+veNvGA0jUbPT4oPs7y7oEcNlcY6sfWgD2qvMfj5/wAktuP+vqH/ANCr06uV+I/hiXxf4F1HSLYqLp1WSDccAupDAZ7Zxj8aAPnr4e/B2Tx74ck1ddaWzCXDQeUbff0CnOdw/vV1n/DM83/Q0J/4BH/4uuC8MePvFvwte80lbONFeTfJa38LfI+MFhgg8gD2OBXRf8NG+LP+gbpH/fqT/wCLoA6/4vaKfDnwO0jRjOJzZ3MERlC7d+EfnHOK0Phvoq+Iv2ejpDDJuo7pE9n8xip/BgDWP8UNcuPEnwD0XWLtIkuLu7id1iBCg4kHGST2rsPgX/ySfTP+us//AKNagDiP2c9ZZI9e8Ozkq6Yuo0PUfwP/AOyVhfs9f8lJ1T/sHy/+jY6g1jUB8K/jxfagbd5LGVnlMUZALxzKTgZ9H/8AQal/Z3cP8RdRYcbtOkIH/bWOgCL4WH7N8friGX5XM15Hg/3huOP0NelfFv4c+IvG2q6dc6JeWsEdvC0cgmndCSWzxtU1wHxa8La14L8f/wDCa6Iji1mmFyJo13CCb+IOPRuTzwckVAP2jfFgAzp2kE/9cpP/AIugCn8DpLlfixBbzTyPshnUguSMhTR8fl3/ABSCZxus4Rn8WqL4Fymf4twSsAGkhnYgdMlSa7H9oHwPqV7f2vifTbaS5hSAQXSxKWaPBJV8DnHJBPbAoAhH7NExUH/hKE5H/Pkf/i62vCXwFl8M+KtO1pvECXAs5fM8oWpXdwRjO4461wdh+0H4wsbGG1lttNuWiUJ5s0T72xxlsMBn8K6Lwh8dvEniDxfpOkXVjpaQXdysUjRxuGAJ7Zc80AYnxN/5OFtP+vmx/wDZK6v9pDQzLpWka9Ep3W8rW0pH91huX8ip/wC+q5P4m/8AJwtp/wBfNj/7JXvHxF0L/hI/h/rOnKoaVrcyQj/ponzL+ZGPxoA8r+J2uDxH8AdA1UsGkmuIRKf+mio6v/48DWp4S/5Nevf+wfff+hSV4l/wl4f4YHwjLDIzpqQvIZsjaqbSCuPqc/ia9t8Jf8mvXv8A2D77/wBCkoA8i+G3w3f4iT6jEmprY/YljbJh8zfuLe4xjb+td3e/s4TWdjcXR8TIwhiaTb9jIzgE4+/7U/8AZo/4/wDxH/1yg/m9e8a3/wAgHUf+vWX/ANBNAHzn+zh/yPGp/wDYOb/0YlVP2hNY+3/EGPT1bMen2qIR/tv85/Qr+VW/2cSB431MkgAacx5/66JWHoEcfxA+OyzTxrcWlzqElwyOMq0KZYA+o2qBQB1eo/Gvw5e+ApvC6aJqCRNYfY43LphSE2qTz2IBqH9m/Wfs/iPVdHd8Ld26zID3aM4P6Ofyr3D/AIQLwh/0LGj/APgHH/hXzXozDwJ8fFgGIreDU3t8DgCGQlR+AVgfwoAt/HtDJ8VGRTgtawgH86yPHHgPxT4Ct7O51LURPBdMUWS2nchWAzg5A5Izj6Gtr47f8laX/r3g/rX0F468LR+MfBV9pDBfOePfbOf4JV5U/nwfYmgDyr4K/DC0Y2HjW61OO8O0vb28Sn93Jyp3k9WHPHrzmuU/aI/5KRB/2Dov/Q5K0vgJ4vk0PxHc+EtSZoobxyYVfjy7heCvtuAx9VHrWb+0R/yUiD/sHRf+hyUAex/FvWP7H+Ed+ytiW7ijtE99+A3/AI6Grw/4U/EjSvh9FqbXmm3V1cXjRgNCygKq54592/Sux/aJ1jGneHdERvvKbuRfoAqfzeuz+GXw/wDDw+HWjTanoWn3V5cQ/aJJbi2V3O8ll5I7KQKAPAfFnjK21j4jjxXpVrNa/vYZ/LlIz5iBeePXaK+x7S6ivbKC7hOYp41kQ+qsMj+dfPv7QPhDStG03RtS0nTLWxTzngmFtCsYYkBlzgf7LfnXpnwc1n+2fhhpLM26W1VrSTnpsOF/8d20Ad5RRRQBDNa29yQZ7eKUr03oGx+dSRxpEgSNFRF4CqMAU6igBksUc8ZjljSRD1VxkH8Kh/s6y2bPsdvszu2+UuM+vSrNFAEcMEVumyGJI0znaigDP4VJRRQBXjsbOKQSR2sCSDoyxgEfjVggEEEZB7UUUAVTptgSSbK2JPcxL/hT4rK0gffDawxvjG5IwD+lT0UAFFFFAEU1tBcY8+COXHTegb+dRf2Zp/8Az423/flf8KwfiJeXVh4G1G5s55YJ0MQWSJ9rDMig4PbgkZpPBltf28V59uj1VCzJs/tDUI7ong/dKfd989eKrl0uK+tjo2tLZ4Fha3iMS9EKDaPwp8UUcEYjijSNB0VFAA/Cn1i+LIdVuPDF7Fos3lagyr5TBwh+8NwDHgErkA+ppJXY2ac1na3D75raGRsYy8YJx+NENna27l4LaGJiMEogU4/CuW8CXTv/AGrY3J1QXlpMgmjv7xbkruQMu114xjtVye8uV+JNlZCeQWr6VNK0OflLiVAGx64J/Ony62FfQ6MqGUqwBB4IPeq39mWH/Pjbf9+l/wAKxfG1vrNzosSaLJKkwuUMyw3CwSPFzuVHbhT0/I03wNeC70GVS1+Zre6lgmF9cCeRXU4I3jgj0xRbS4X1sb8VjaQSb4bWCNx/EkYB/Sp64nx1Z3DajoUlvrGqWYvL+OyljtbjYhQq7E4x97IHPpXZxR+VCke9n2KF3OcscdyfWk1pcEyF9PspGLPZ27MepaJSf5UJp9lG4eOzt1dTkMsSgj9K830Z9Y1DxhqErSa3PbW+sSQ7otTjSCNFYYUxH5iAPTqOleo05RsCdyB7O1km82S2haUY+dkBPHTmp68YTXtbD6zYnVrszaneCGxYycw7bxonCenyEflXovgO7uL/AMD6RdXU8k88kGXlkOWY5PJNOULK4lK5sf2Zp/8Az423/fpf8KmW3hSAwLDGIiCPLCjbg9eK4r4j6rNbLpWmW9/eWL3kkrvPZqzSKscZIGFBOC7IDxXQ+FNVOt+FNL1FzmSe3Qyf74GG/wDHgaTi7XHfWxpQ2tvbEmCCKLd12IFz+VSkBgQQCDwQa8/8fLrcGo/2hFLqJ0W3smeVNPv0tpEcElmO4fMNuMAeldzYTJcadazxM7RyRI6mT7xBAIz70NWVwT1sLFZ2sDFobaGMkYJSMDI9OKIrK0gffDawxv03JGAf0qeipGFV3sbSWUyyWsDyHks0YJ/OrFFAEEtlazyeZLbQyP8A3njBP51PRRQBX+wWfm+b9kg8zdu3+WM59c+tLNZWtw++a2hkbGNzxgnH41PRQBBLZ2twwaa2hkYDALxgkD8amVVRQqgBQMAAcAUtFAEc0ENwmyaJJFzna6gjP40QwQ26bIYkiUnO1FCjP4VJRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUARXVrb3trLa3UMc0EqlXjkUMrA9iDVHSPD2kaAsy6Vp8FoJiDIIlxuxnGfzNFFO72A06rahp1nqtjJZX9ulxbSY3xSDIbByP1AoopAQ6TommaFbvb6XYwWkTtvZYlxuPqfWp2sbVr9L8wIbpIzEsuPmCEglfpkD8qKKdwIdV0fTtctBa6nZxXUAcOI5RkBhkA/qafp2mWOkWSWenWsVtbISVjiXABPU0UUXewD7qxtb1rdrmBJTbyiaIsM7HAIDD3wT+dWKKKQGPN4U0C41ddWl0m1a/VxILjy8NuHQ59eBWxRRTu2Bljw3owube4/s23863leaF9vKO5yzD3J5q7ZWVtp1nFZ2cKQW8Q2xxoMBR7UUUXYWEaxtXv479oEN1HGYklI+ZVJBIH1IH5UWNha6bbC2soEggDMwRBgAsSSfxJJoopAZ+q+FdC1y6S61TSra7nRQivKmSFBJx9Mk1rqqooVVCqBgADAAoop3YC0UUUgCiiigAooooAKKKKACiiigAooooAKKKKAP/Z',true);
do $$
declare axe uuid:=(select id from public.erp_empresas where cnpj='39893713000167');
begin
 execute format('alter table public.imp_pedidos add column empresa_id uuid not null default %L::uuid references public.erp_empresas(id)',axe);
end $$;

alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_empresas;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
 a text:=p_dados->>'acao';
 d jsonb:=p_dados->'dados';
 r jsonb;
 empresa public.erp_empresas;
 pedido public.imp_pedidos;
 eid uuid;
 cnpj_doc text;
 logo_doc text;
 admin boolean;
 antes jsonb;
begin
 if a in ('v2_empresas_listar','v2_empresa_salvar') then
  perform public.axe_imp_estrutura_sem_empresas('{"acao":"v2_opcoes"}',p_usuario);
  select exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo and papel='ADMIN') into admin;
  if a='v2_empresas_listar' then
   return jsonb_build_object('editar',admin,'linhas',(select coalesce(jsonb_agg(to_jsonb(e) order by e.razao_social),'[]') from public.erp_empresas e));
  end if;
  if not admin then raise exception 'Apenas administradores podem alterar empresas';end if;
  eid:=nullif(d->>'id','')::uuid;
  cnpj_doc:=regexp_replace(coalesce(d->>'cnpj',''),'[^0-9]','','g');
  logo_doc:=nullif(d->>'logo','');
  if coalesce(length(btrim(d->>'razao_social')),0) not between 1 and 200
    or coalesce(length(btrim(d->>'endereco')),0) not between 1 and 600 or cnpj_doc !~ '^[0-9]{14}$'
    or (logo_doc is not null and (octet_length(logo_doc)>200050 or logo_doc !~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/]+={0,2}$')) then
   raise exception 'Confira razão social, CNPJ, endereço e logotipo';
  end if;
  if eid is null then
   insert into public.erp_empresas(razao_social,nome_fantasia,cnpj,inscricao_estadual,endereco,endereco_entrega,email,telefone,logo,atualizado_por)
   values(btrim(d->>'razao_social'),left(nullif(btrim(d->>'nome_fantasia'),''),200),cnpj_doc,left(nullif(btrim(d->>'inscricao_estadual'),''),40),
    btrim(d->>'endereco'),left(nullif(btrim(d->>'endereco_entrega'),''),600),left(nullif(btrim(d->>'email'),''),254),left(nullif(btrim(d->>'telefone'),''),60),logo_doc,p_usuario)
   returning * into empresa;
  else
   update public.erp_empresas e set razao_social=btrim(d->>'razao_social'),nome_fantasia=left(nullif(btrim(d->>'nome_fantasia'),''),200),
    inscricao_estadual=left(nullif(btrim(d->>'inscricao_estadual'),''),40),endereco=btrim(d->>'endereco'),
    endereco_entrega=left(nullif(btrim(d->>'endereco_entrega'),''),600),email=left(nullif(btrim(d->>'email'),''),254),
    telefone=left(nullif(btrim(d->>'telefone'),''),60),logo=coalesce(logo_doc,e.logo),versao=e.versao+1,
    atualizado_por=p_usuario,atualizado_em=clock_timestamp()
   where e.id=eid and e.versao=(d->>'versao')::int and e.cnpj=cnpj_doc returning * into empresa;
   if not found then raise exception 'Cadastro atualizado por outra operação ou CNPJ alterado. Reabra o cadastro';end if;
  end if;
  return to_jsonb(empresa);
 end if;

 if a='v2_salvar' and p_dados->>'tipo'='pedidos' and nullif(d->>'empresa_id','') is not null then
  perform pg_advisory_xact_lock(728102826);
  if exists(select 1 from public.imp_requisicoes where usuario_id=p_usuario and requisicao_id=(p_dados->>'requisicao_id')::uuid) then
   return public.axe_imp_estrutura_sem_empresas(p_dados,p_usuario);
  end if;
  eid:=(d->>'empresa_id')::uuid;
  select * into empresa from public.erp_empresas where id=eid and ativa;
  if not found then raise exception 'Selecione uma empresa emissora ativa';end if;
  select * into pedido from public.imp_pedidos where id=nullif(p_dados->>'id','')::uuid for update;
  if pedido.id is not null and pedido.status<>'Elaboração' and pedido.empresa_id<>eid then
   raise exception 'A empresa emissora só pode mudar enquanto o pedido estiver em elaboração';
  end if;
  r:=public.axe_imp_estrutura_sem_empresas(p_dados,p_usuario);
  select to_jsonb(p) into antes from public.imp_pedidos p where p.id=(r->>'id')::uuid;
  update public.imp_pedidos p set empresa_id=eid where p.id=(r->>'id')::uuid and p.empresa_id<>eid returning * into pedido;
  if found then
   insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)
   values('pedidos',pedido.id,p_usuario,antes,to_jsonb(pedido));
  end if;
  return r;
 end if;

 r:=public.axe_imp_estrutura_sem_empresas(p_dados,p_usuario);
 if a='v2_opcoes' then
  return r||jsonb_build_object('empresas',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'nome',e.razao_social,'padrao',e.logo_padrao) order by e.logo_padrao desc,e.razao_social),'[]')
   from public.erp_empresas e where e.ativa));
 elsif a='v2_pedido_pdf' then
  select * into empresa from public.erp_empresas where id=(r#>>'{pedido,empresa_id}')::uuid;
  if empresa.id is null then raise exception 'Empresa emissora não encontrada';end if;
  return r||jsonb_build_object('empresa',to_jsonb(empresa)-'atualizado_por');
 end if;
 return r;
end $$;
revoke all on function public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_estrutura(jsonb,uuid) to service_role;
